#!/usr/bin/env bash
# Tests for the ai-modes hooks: user-only switching, phases and freezes, the guard, pair-unlock,
# tamper detection and the debt report. Runs the hooks from this checkout against a throwaway HOME, so your
# real ~/.claude is never touched. Usage: tests/aimodes-test.sh  (needs bash and jq).
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/claude/hooks"
T=$(mktemp -d)
export HOME=$T
mkdir -p $T/.claude/hooks $T/.claude/ai-mode/sessions $T/.claude/ai-mode/unlocked
for h in $REPO/*.sh; do ln -s $h $T/.claude/hooks/$(basename $h); done
mkdir -p $T/.claude/skills; ln -s $REPO/../skills/phase $T/.claude/skills/phase
B=$T/.claude/hooks/mode-banner.sh G=$T/.claude/hooks/mode-guard.sh
E=$T/.claude/ai-mode/events.tsv S=$T/.claude/ai-mode/sessions
pass=0 fail=0
ok(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1 | want [$3] got [$2]"; fi; }
banner(){ jq -nc --arg s "$1" --arg p "$2" '{session_id:$s,prompt:$p}' | bash $B; }
mode(){ cat $S/$1 2>/dev/null || echo none; }
guard(){ local r; r=$(jq -nc --arg s "$1" --arg t "$2" --arg c "$3" --arg f "$4" \
  '{session_id:$s,tool_name:$t,tool_input:{command:$c,file_path:$f},cwd:"/tmp"}' | bash $G \
  | jq -r '.hookSpecificOutput.permissionDecision // "allow"'); echo "${r:-allow}"; }

# A: user switches through the prompt hook
banner s1 "/solve" | head -1 >/dev/null;               ok "raw /solve switches"        "$(mode s1)" plan:solve
ok "row tagged user" "$(tail -1 $E | cut -f5)" user
banner s1 "<command-message>pair</command-message>
<command-name>/pair</command-name>" >/dev/null;         ok "tag form switches"          "$(mode s1)" plan:pair
banner s1 "please /solve this" >/dev/null;             ok "mid-sentence ignored"       "$(mode s1)" plan:pair
banner s1 "/solver idea" >/dev/null;                   ok "prefix word ignored"        "$(mode s1)" plan:pair
banner s2 "hello" >/dev/null;                          ok "no file created"            "$(mode s2)" none
out=$(banner s1 "/study now"); ok "banner shows study"  "$(printf '%s' "$out" | command grep -c 'AI-MODE: study')" 1

# A: guard denies agent switching and state writes in every mode
SW='~/.claude/hooks/mode-set.sh'
for m in solve pair study; do
  printf '%s' $m > $S/g1
  ok "$m: run switch"        "$(guard g1 Bash "$SW solve" "")" deny
  ok "$m: env+bash switch"   "$(guard g1 Bash "A=1 bash $SW solve" "")" deny
  ok "$m: subshell switch"   "$(guard g1 Bash "x=\$($SW solve)" "")" deny
  ok "$m: chained switch"    "$(guard g1 Bash "cd /tmp && ./mode-set.sh solve" "")" deny
  ok "$m: read allowed"      "$(guard g1 Bash "cat $SW" "")" allow
  ok "$m: grep allowed"      "$(guard g1 Bash "grep -n x claude/hooks/mode-set.sh" "")" allow
  ok "$m: redirect state"    "$(guard g1 Bash "printf solve > ~/.claude/ai-mode/sessions/g1" "")" deny
  ok "$m: Write state"       "$(guard g1 Write "" "$T/.claude/ai-mode/guard.conf")" deny
done
printf pair > $S/g1
ok "pair: guard code via symlink locked" "$(guard g1 Edit "" "$T/.claude/hooks/mode-guard.sh")" deny
ok "pair: other ~/.claude still exempt"  "$(guard g1 Write "" "$T/.claude/projects/x/memory/a.md")" allow
printf solve > $S/g1
ok "solve: guard code editable"          "$(guard g1 Edit "" "$T/.claude/hooks/mode-guard.sh")" allow
ok "solve: ordinary write allowed"       "$(guard g1 Write "" "/tmp/x.py")" allow

# pair-unlock refuses guard code and state
out=$(cd /tmp && CLAUDE_CODE_SESSION_ID=u1 bash $T/.claude/hooks/pair-unlock.sh $T/.claude/hooks/mode-guard.sh $T/.claude/ai-mode/x /tmp/ok.py 2>&1)
ok "unlock refuses guard+state" "$(printf '%s' "$out" | command grep -c refused)" 2
ok "unlock keeps normal path"   "$(cat $T/.claude/ai-mode/unlocked/u1)" /tmp/ok.py

# C: tamper detection
banner c1 "/pair" >/dev/null
printf solve > $S/c1                                   # direct file write
out=$(banner c1 "next")
ok "tamper restored"        "$(mode c1)" plan:pair
ok "tamper alert shown"     "$(printf '%s' "$out" | command grep -c 'AI-MODE ALERT')" 1
ok "revert logged"          "$(tail -1 $E | cut -f3-5 | tr '\t' ' ')" "solve plan:pair revert"
CLAUDE_CODE_SESSION_ID=c1 bash $T/.claude/hooks/mode-set.sh plan:solve >/dev/null   # direct script call
ok "direct row tagged"      "$(tail -1 $E | cut -f5)" direct
banner c1 "next" >/dev/null; ok "direct call reverted" "$(mode c1)" plan:pair
printf '2026-01-01T00:00:00Z\tl1\tpair\tsolve\n' >> $E; printf solve > $S/l1
banner l1 "next" >/dev/null; ok "legacy row trusted"   "$(mode l1)" solve
rm $S/c1; banner c1 "next" >/dev/null; ok "deleted file stays pair" "$(mode c1)" none

# Phases: fresh session, switching, rejection
out=$(banner p0 "hello")
ok "fresh: banner pair"            "$(printf '%s' "$out" | command grep -c 'AI-MODE: pair')" 1
ok "fresh: banner phase plan"      "$(printf '%s' "$out" | command grep -c 'AI-PHASE: plan')" 1
ok "fresh: no file"                "$(mode p0)" none
banner p1 "/phase implement" >/dev/null; ok "/phase implement"      "$(mode p1)" implement:pair
ok "phase row"                     "$(tail -1 $E | cut -f3-5 | tr '\t' ' ')" "plan:pair implement:pair user"
out=$(banner p1 "/solve");         ok "mode keeps phase"    "$(mode p1)" implement:solve
ok "implement banner names freeze" "$(printf '%s' "$out" | command grep -c 'AI-PHASE: implement')" 1
banner p1 "<command-message>phase</command-message>
<command-name>/phase</command-name>
<command-args>plan</command-args>" >/dev/null;  ok "tag form /phase plan" "$(mode p1)" plan:solve
rows=$(wc -l < $E)
out=$(banner p1 "/phase");         ok "bare /phase rejected"   "$(mode p1)" plan:solve
ok "bare /phase notice"            "$(printf '%s' "$out" | command grep -c 'AI-PHASE REJECTED')" 1
out=$(banner p1 "/phase design");  ok "unknown phase rejected" "$(mode p1)" plan:solve
ok "unknown phase notice"          "$(printf '%s' "$out" | command grep -c 'AI-PHASE REJECTED')" 1
banner p1 "/phaser x" >/dev/null;  ok "/phaser ignored"        "$(mode p1)" plan:solve
ok "rejections write no row"       "$(wc -l < $E)" "$rows"
banner p1 "/phase implement extra words" >/dev/null; ok "/phase with trailing text" "$(mode p1)" implement:solve

# Legacy mode-only state reads as plan:<mode>
printf '2026-01-01T00:00:00Z\tl2\tpair\tsolve\n' >> $E; printf solve > $S/l2
out=$(banner l2 "next")
ok "legacy: no revert"             "$(mode l2)" solve
ok "legacy: banner solve"          "$(printf '%s' "$out" | command grep -c 'AI-MODE: solve')" 1
ok "legacy: banner plan"           "$(printf '%s' "$out" | command grep -c 'AI-PHASE: plan')" 1
banner l2 "/phase implement" >/dev/null; ok "legacy: /phase keeps mode" "$(mode l2)" implement:solve

# Phase tamper: a changed phase or an invalid file is restored
banner t1 "/phase implement" >/dev/null
printf plan:pair > $S/t1;   out=$(banner t1 "next")
ok "phase tamper restored"         "$(mode t1)" implement:pair
ok "phase tamper alert"            "$(printf '%s' "$out" | command grep -c 'AI-MODE ALERT')" 1
ok "phase revert logged"           "$(tail -1 $E | cut -f3-5 | tr '\t' ' ')" "plan:pair implement:pair revert"
printf 'implement:yolo' > $S/t1; banner t1 "next" >/dev/null; ok "invalid mode restored"  "$(mode t1)" implement:pair
printf 'garbage' > $S/t1;        banner t1 "next" >/dev/null; ok "invalid value restored" "$(mode t1)" implement:pair
CLAUDE_CODE_SESSION_ID=t1 AI_MODE_SOURCE=user bash $T/.claude/hooks/mode-set.sh implement >/dev/null 2>&1
ok "mode-set rejects half state"   "$(mode t1)" implement:pair

# Freezes: paths relative to the containing repo's root, in every mode
R=$T/repo; mkdir -p $R && git -C $R init -q && git -C $R -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
mkdir -p $R/.requirements/c1 $R/.system_design
for m in pair solve study; do
  printf implement:$m > $S/f1
  ok "impl:$m spec Write"          "$(guard f1 Write "" "$R/.requirements/c1/REQUIREMENTS.md")" deny
  ok "impl:$m spec redirect"       "$(guard f1 Bash "echo x > $R/.requirements/c1/REQUIREMENTS.md" "")" deny
  ok "impl:$m design doc"          "$(guard f1 Edit "" "$R/.system_design/SYSTEM_DESIGN.md")" deny
  ok "impl:$m adr"                 "$(guard f1 Write "" "$R/docs/adr/0001-x.md")" deny
done
out=$(jq -nc --arg f "$R/.requirements/c1/REQUIREMENTS.md" '{session_id:"f1",tool_name:"Write",tool_input:{file_path:$f},cwd:"/tmp"}' | bash $G | jq -r '.hookSpecificOutput.permissionDecisionReason')
ok "freeze reason names it frozen" "$(printf '%s' "$out" | command grep -c 'frozen')" 1
printf implement:solve > $S/f1
ok "impl: PLAN.md writable"        "$(guard f1 Write "" "$R/.requirements/c1/PLAN.md")" allow
ok "impl: code writable"           "$(guard f1 Write "" "$R/src/a.py")" allow
ok "impl: new spec dir still found" "$(guard f1 Write "" "$R/.requirements/new/REQUIREMENTS.md")" deny
ok "impl: nested .requirements not root" "$(guard f1 Write "" "$R/sub/.requirements/x/REQUIREMENTS.md")" allow
ok "impl: outside repo no freeze"  "$(guard f1 Write "" "$T/norepo/.requirements/x/REQUIREMENTS.md")" allow
printf plan:solve > $S/f1
ok "plan: spec writable"           "$(guard f1 Write "" "$R/.requirements/c1/REQUIREMENTS.md")" allow
printf solve > $S/f1
ok "legacy: spec writable"         "$(guard f1 Write "" "$R/.requirements/c1/REQUIREMENTS.md")" allow

# Worktree: matched relative to the worktree root
git -C $R worktree add -q $T/wt 2>/dev/null
printf implement:solve > $S/f1
ok "worktree spec frozen"          "$(guard f1 Write "" "$T/wt/.requirements/c1/REQUIREMENTS.md")" deny
ok "worktree code writable"        "$(guard f1 Write "" "$T/wt/src/a.py")" allow

# Per-repo override and guard.conf classes
git -C $R config --local ai-modes.spec 'specs/**'
ok "override: specs frozen"        "$(guard f1 Write "" "$R/specs/a/b.md")" deny
ok "override: default spec free"   "$(guard f1 Write "" "$R/.requirements/c1/REQUIREMENTS.md")" allow
ok "override shared by worktree"   "$(guard f1 Write "" "$T/wt/specs/a.md")" deny
git -C $R config --local --unset ai-modes.spec
cp $REPO/../ai-mode/guard.conf $T/.claude/ai-mode/guard.conf
printf '%s\n' "CLASS_DESIGN='arch/*.md'" >> $T/.claude/ai-mode/guard.conf
ok "guard.conf design class"       "$(guard f1 Write "" "$R/arch/a.md")" deny
ok "single * stays in segment"     "$(guard f1 Write "" "$R/arch/x/a.md")" allow
ok "guard.conf spec default kept"  "$(guard f1 Write "" "$R/.requirements/c1/REQUIREMENTS.md")" deny
rm $T/.claude/ai-mode/guard.conf

# The phase skill is guard code: locked in pair
printf implement:pair > $S/f1
ok "pair: phase skill locked"      "$(guard f1 Edit "" "$T/.claude/skills/phase/SKILL.md")" deny

# debt report provenance
rep=$(bash $T/.claude/hooks/debt.sh report)
ok "debt counts mode, not phase" "$(printf '%s' "$rep" | command grep -c 'switched to solve  *4 times')" 1
ok "debt shows provenance" "$(printf '%s' "$rep" | command grep -c 'switches not made by the user: 1 direct, 5 reverted')" 1

echo "pass=$pass fail=$fail"
rm -rf "$T"
[ "$fail" -eq 0 ]
