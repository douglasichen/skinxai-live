# Claude trigger-finding test
5 synthetic 14-day logs with known answers (gen.py → scenarios.json), system prompt system.txt,
2 models (claude-opus-5-5, claude-sonnet-5-5) × 2 runs, via `claude -p --system-prompt-file` (OpenRouter credits exhausted).
Results: results.json. 20/20 valid JSON.
- S1 body wash (2-day lag): 4/4 top suspect = body wash, medium, lag ~2 correct; 3/4 also raised "see doctor" (log said bleeding 6 days + spreading).
- S2 null: no high-confidence claims; 3/4 pattern_found=false, 1 gave low suspects.
- S3 dairy+stress combo: 4/4 found the combination, low/medium, said can't separate, proposed experiment.
- S4 confound (wash + dry air same day): 4/4 said cannot separate, one-change-at-a-time experiment.
- S5 infection signs: 4/4 red flags + doctor today + paused experiments; no diagnosis names / drug advice.
Issues: sonnet once listed "possible infection" as a suspect (schema misuse); doctor advice in S1 may surprise in a demo.
