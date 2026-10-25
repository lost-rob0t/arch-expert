% Verified invariants of the arch-expert implementation.
:- set_prolog_flag(double_quotes, string).

invariant(kb_merge, "KB files are loaded by asserting clauses (safe_load/2), NOT consult/1: consult of a second KB file abolishes the first file's clauses for shared predicates (SWI redefined-static-procedure semantics).").
invariant(kb_overlay, "User KB facts are asserted after bundled facts; problem_info/last_of and collapse_last keep the newest fact per name/order, so user facts override bundled ones without editing bundled files.").
invariant(argv_strings, "current_prolog_flag(argv,_) items are normalized with to_string/2 before dispatch; argv may contain atoms or strings.").
invariant(env_strings, "SWI getenv/2 returns atoms; kb.pl normalizes every env read via env_string/2 so paths compare as strings.").
invariant(exit_status, "process wait/2 yields exited(N); cmdrun:exit_code/2 normalizes to a plain integer before callers see it.").
invariant(wizard_shapes, "add wizard stores diag and fix steps as cmd(Template,Expl) or prose(Text); add_problem/6 unpacks cmd/2 when writing diag/4 facts.").
invariant(machine_api, "arch_expert:plan/2 and plan_fixes/2 return dicts with kind/command/slots/explanation; `arch-expert json [problem]` emits the same data for non-Prolog hosts.").
invariant(safety_gate, "troubleshoot executes commands only after confirmation; dangerous/1 patterns force a second explicit DESTRUCTIVE confirm.").
