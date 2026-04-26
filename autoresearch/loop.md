# /loop driver prompt

Use this as the argument to Claude Code's `/loop` command to run the
autoresearch agent. Self-paced (no fixed interval) — Claude decides when
to wake up, but each iteration should aim for ~5 minutes wall-clock.

```
/loop
```

Then paste the prompt below at the prompt that follows, or run:

```
/loop Read autoresearch/program.md and run one experiment iteration. Read autoresearch/log.jsonl and autoresearch/best.txt for state. Snapshot, edit src/, run autoresearch/run_iteration.sh "<change summary>", then keep-or-revert per the rules. Stop after one iteration.
```

## Manual single-shot (no loop)

```
Read autoresearch/program.md and autoresearch/best.txt and the last 10 lines of autoresearch/log.jsonl. Pick one technique from the backlog. Snapshot src/, apply the change, run autoresearch/run_iteration.sh "<summary>", then keep or revert.
```
