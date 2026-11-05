# How a CSR notification becomes a trace (RTL and C++)

## The short version

There are two independent implementations of the same instruction:

- **RTL:** the CSR execution/commit logic produces `csr_notif`. The top-level uses that notification, plus `commit_notif` and the redirect notification, to build one `arch_trace_t` event.
- **C++ functional model:** `FLProc::step()` executes that instruction in the software model. It updates the model's CSR values and returns an `FLTrace` describing the instruction's architectural event.

The test compares the RTL trace event with the C++ `FLTrace` event. The C++ model does not consume the RTL notification; the two sides produce their own event from their own execution.

## RTL path: notification to exported trace

`CSRNotif` is an interface carrying one commit-time CSR-related action. Its fields are in [`intf/CSRNotif.v`](intf/CSRNotif.v):

- `val`: this notification is active.
- `cmd`, `addr`, `wdata`: CSR operation and its operands.
- `exc_val`, `exc_cause`, `pc`: exception information associated with the instruction.

In [`hw/top/BlimpV9_csr.v`](hw/top/BlimpV9_csr.v), the trace event is assembled from the commit and notification signals:

```systemverilog
assign trace_enq_msg.pc               = commit_notif.pc;
assign trace_enq_msg.gen_regs_waddr   = commit_notif.waddr;
assign trace_enq_msg.gen_regs_wdata   = commit_notif.wdata;
assign trace_enq_msg.gen_regs_wen     = commit_notif.wen;
assign trace_enq_msg.trap             = csr_notif.val & csr_notif.exc_val;
assign trace_enq_msg.trap_cause       = csr_notif.exc_cause;
assign trace_enq_msg.redirect_valid   = squash_arb_notif[2].val;
assign trace_enq_msg.redirect_pc      = squash_arb_notif[2].target;
assign trace_enq_msg.csr_action_valid  = csr_notif.val;
assign trace_enq_msg.csr_cmd          = csr_notif.cmd;
assign trace_enq_msg.csr_addr         = csr_notif.addr;
assign trace_enq_msg.csr_wdata        = csr_notif.wdata;
assign trace_enq_val                  = commit_notif.val;
```

In plain language: when `commit_notif.val` says an instruction commits, the top-level captures its PC and GPR writeback. If the CSR notification is active, it copies the CSR action into the trace. Trap and redirect fields describe trap entry or return. The completed message is then exposed through `inst_trace.arch` (after the trace queue).

`CSRNotif` describes **one instruction's action**, not a full dump of the CSR register bank. A CSR instruction names one CSR, so its action is one command/address/source operand. Trap entry is different: the CSR file can update several CSRs (`mepc`, `mcause`, `mtval`, and `mstatus`) for one trap. Those resulting values are not all carried in this action trace; the trace records the trap cause/value and redirect information instead.

## C++ path: execute instruction, update model, make matching event

The CSR instruction handling is in [`fl/FLProc.cpp`](fl/FLProc.cpp), inside `FLProc::step()`:

```cpp
uint32_t source = immediate ? inst.uimm() : regs[inst.rs1()];
uint32_t cmd = exchange ? FLTrace::CSR_CMD_WRITE
             : ( inst_name == CSRRS || inst_name == CSRRSI )
                 ? FLTrace::CSR_CMD_SET : FLTrace::CSR_CMD_CLEAR;
uint32_t old_val = ( exchange && inst.rd() == 0 )
                     ? 0 : csr.read( addr );

if ( write ) {
  uint32_t new_val = source;
  if ( inst_name == CSRRS || inst_name == CSRRSI )
    new_val = old_val | source;
  else if ( inst_name == CSRRC || inst_name == CSRRCI )
    new_val = old_val & ~source;
  csr.write( addr, new_val );       // Update the software model's CSR state
}

// The instruction's normal GPR result is old_val (when rd is not x0).
FLTrace trace( inst_pc, inst.rd(), old_val, inst.rd() != 0 );
trace.set_csr_action( cmd, addr, source );
return trace;
```

This does two related but distinct jobs: `csr.write()` changes the functional model's internal state so later instructions see the new value; `set_csr_action()` puts the instruction's operation into the trace so it can be compared with RTL. The trace carries the source operand, not the already-computed new CSR value. Both sides interpret the command using the old CSR value.

The trace fields are set by [`FLTrace::set_csr_action()` in `fl/FLTrace.cpp`](fl/FLTrace.cpp):

```cpp
csr_action_valid = true;
csr_cmd = cmd;
csr_addr = addr;
csr_wdata = data;
```

## What happens for a trap or MRET?

**Trap entry:** `FLProc::take_trap()` calls `csr.enter_trap(...)`, which updates the model's trap CSRs and returns the trap-handler PC. It then returns an `FLTrace` with trap cause/value and redirect target. See [`fl/FLProc.cpp`](fl/FLProc.cpp) and [`fl/FLCSRfile.cpp`](fl/FLCSRfile.cpp).

**MRET:** `FLProc::step()` calls `csr.return_from_trap()`, which restores the modeled interrupt-status bits and returns `mepc` as the target. The returned `FLTrace` records a redirect and the `MRET` command.

So, conceptually, yes: both RTL and C++ report the instruction's high-level architectural event. They do not share the same notification object. RTL derives its event from RTL commit notifications; C++ derives its event while executing the instruction in the reference model.

## Where comparison happens

The C++ `FLTrace` is packed into the same `arch_trace_t` word layout by `FLTrace::arch_vrep()` in [`fl/FLTrace.cpp`](fl/FLTrace.cpp). The Verilog test receives that packed event and compares its fields against the RTL trace. Thus the comparison is **RTL-produced trace vs. C++-produced trace**, instruction by instruction.

## One important scope detail

The current event is an **instruction/action trace**, not a complete architectural-state snapshot after every instruction. For a CSR write, it says which CSR command was issued and with what source. It does not contain every CSR's post-instruction value. Trap entry changes multiple internal CSR values, but the event reports trap metadata and control-flow redirect rather than enumerating each changed CSR.

## Change log

- Created `TRACE_NOTIF_TO_CPP.md` to explain, in one place, how the RTL commit notification becomes an exported trace event and how the C++ functional model independently updates its CSR state and creates the matching `FLTrace`. Added this because the two paths were easy to conflate when reading source files separately.
