• The pilot confirms the harness works, but it does not yet cleanly answer “does the LLM know Python better than
  Sigil?”

  - Python passed all 12/12 conditions.
  - Sigil passed 8/12 fully; every miss was the same invoice hidden group.
  - On average, Sigil used 32.5 recorded tool events and 181 seconds per trial, versus Python’s 14.5 and 89
    seconds. That is a real preliminary usability/effort signal, but only one run per condition.

  The four Sigil invoice failures are not ordinary coding mistakes. Each implementation correctly used quotient
  for the specified floor calculation, then crashed with:

  quotient: expected exact integers

  The hidden case makes the intermediate subtotal * discount_bp about 1e16. Sigil can calculate the roughly 1e12
  subtotal, but that larger intermediate becomes inexact and quotient rejects it. Python’s standard integers are
  arbitrary precision, so it succeeds naturally.

  So there are two valid interpretations:

  - If the question is “which language/runtime can these agents use more reliably for this real task?”, Python
    won decisively: 12/12 complete passes, faster completion, and fewer tool interactions.

  - If the question is specifically “does popular-language training knowledge make the LLM better at Python
    syntax and APIs?”, the invoice result is confounded by an unstated Sigil numeric-range requirement. The task
    silently requires overflow-safe arithmetic in Sigil, but neither the task nor the reference card teaches that
    technique.

  The reference arm showed no score improvement because all successful cells were already at ceiling, and the
  supplied Sigil reference did not address exactness/overflow. It may have reduced time and tool use in several
  Sigil cells, but with one run per cell that is only suggestive.

  The “95% confidence intervals” are not meaningful yet: each comparison has n = 1, so bootstrap resampling
  necessarily returns the same one observation. The report is a pilot validation, not a statistical conclusion.

  For the full experiment, I’d split the question:

  1. Keep this invoice test as a runtime-capability benchmark, explicitly documenting that it tests overflow-safe
     arithmetic.

  2. Add a language-familiarity invoice variant whose intermediate values remain within Sigil’s exact numeric
     range, or provide both language cards with an overflow-safe decomposition.

  3. Run the planned 10 repetitions before drawing comparative conclusions.
