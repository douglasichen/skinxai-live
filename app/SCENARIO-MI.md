# Scenario: one hidden ingredient (methylisothiazolinone, MI)

Approved by Douglas 2026-10-25. The app shows raw data only: no verdicts, no highlighting of MI, no
"common ingredient" hints anywhere in the UI. Claude (Insight) must find MI itself from the tools.

Nights: −60 … 13 (night n = Oct 10 + n when today is Sat Oct 24; −60 = Tue Aug 11, 13 = Fri Oct 23).
Usual ≈ 12 min/night. Four short flares, each starting the night after a different new product arrived.

## Flares

| # | Flare nights (dates)        | Minutes            | New product(s) bought the day before (order day = first flare night − 1) |
|---|-----------------------------|--------------------|--------------------------------------------------------------------------|
| 1 | −46 … −43 (Aug 25–28)       | 18, 24, 26, 17     | Summit Peak Mint Shampoo, travel size 3 fl oz (order day −47, Aug 24) — trip to Seattle Aug 24–27 (calendar). Travel size ran out → flare ended. |
| 2 | −27 … −24 (Sep 13–16)       | 17, 22, 25, 19     | Lumen Citrus Foaming Hand Soap (order day −28, Sep 12). Overlaps the mid-Sep exam week (−26 … −23) and a dry spell (humidity −28: 31, −27: 29, −26: 30). Exam night −23 is back to normal (13). He stopped using the soap (only asking can tell). |
| 3 | −4 … −1 (Oct 6–9)           | 19, 27, 31, 22     | Northfield Lambswool Crewneck Sweater AND FreshMeadow Spring Bloom Detergent, trial size (both order day −5, Oct 5). The trial size lasted 4 loads → flare ended. He kept wearing the sweater after (only asking can tell). |
| 4 | 10 … 13 (Oct 20–23, now)    | StageStory's own   | Brightwell Sensitive Fragrance-Free Body Wash, 18 fl oz (order day 9, Oct 19). "Fragrance-free, for sensitive skin" — he picked it to be safe. |

Everything else ≈ usual (keep the existing noise). Keep the existing calm dry days elsewhere, the gym
nights, the hoodie/T-shirt/socks, the midterms (nights 1–3, calm).

## Ingredient lists (label order). MI is in all four flare products and in nothing he tolerates.

- Summit Peak Mint Shampoo, travel size 3 fl oz (new, personal care): Water, Sodium Laureth Sulfate,
  Cocamidopropyl Betaine, Fragrance (Parfum), Menthol, Sodium Chloride, Methylchloroisothiazolinone,
  Methylisothiazolinone, Citric Acid
- Lumen Citrus Foaming Hand Soap (new, household): Water, Sodium Laureth Sulfate, Glycerin,
  Fragrance (Parfum), Limonene, Methylisothiazolinone, Tetrasodium EDTA
- FreshMeadow Spring Bloom Detergent, trial size (new, household): Water, Sodium Laureth Sulfate,
  Alcohol Ethoxylate, Sodium Citrate, Fragrance, Methylisothiazolinone, Colorant
- Northfield Lambswool Crewneck Sweater (new, clothing): material "100% lambswool"
- Brightwell Sensitive Fragrance-Free Body Wash, 18 fl oz (new, personal care): Water, Sodium Laureth
  Sulfate, Cocamidopropyl Betaine, Glycerin, Sodium Chloride, Methylisothiazolinone, Citric Acid
  (NO fragrance)

New products with NO flare (decoys; each with ingredients/material):
- Aug 15 (order day −56) Coastline Mineral Sunscreen SPF 30 (personal care): Zinc Oxide, Water,
  Caprylic/Capric Triglyceride, Glycerin, Phenoxyethanol, Tocopherol — used on sunny days
- Sep 2 (order day −38) Alder & Pine Cedar Deodorant (personal care, daily since): Propylene Glycol,
  Water, Sodium Stearate, Fragrance (Parfum), Linalool, Limonene, Sodium Benzoate
  → fragrance and limonene are tolerated daily
- Sep 22 (order day −18) Harbor Oat Daily Lotion (personal care, daily since): Water, Glycerin,
  Colloidal Oatmeal, Cetearyl Alcohol, Dimethicone, Phenoxyethanol, Sodium Benzoate
- Oct 1 (order day −9) Cloudrest Memory Foam Pillow (household): material "polyurethane foam,
  polyester cover"
- keep: hoodie, T-shirt pack, Darn Tough Merino Wool Socks (washed before wearing)

Repeat purchases he has used for years (with ingredients, no MI) — fictional brands since we list
ingredients:
- Everclean Free & Clear Liquid Detergent, 92 loads (monthly; replaces "Tide Free & Clear"):
  Water, Sodium Laureth Sulfate, Alcohol Ethoxylate, Sodium Citrate, Sodium Benzoate, Enzymes
- Riverstone Daily Shampoo, 16 fl oz (repeat, every ~6 weeks): Water, Sodium Laureth Sulfate,
  Cocamidopropyl Betaine, Glycerin, Fragrance (Parfum), Sodium Benzoate, Citric Acid
  → SLS, betaine and fragrance are tolerated
- Dermacalm Ceramide Cream, 16 oz (replaces "CeraVe"): Water, Glycerin, Ceramide NP, Cetearyl
  Alcohol, Petrolatum, Phenoxyethanol
- Willow Unscented Hand Soap Refill (replaces "Method"): Water, Sodium Laureth Sulfate, Glycerin,
  Cocamidopropyl Betaine, Sodium Benzoate, Citric Acid
- Non-skin repeat items keep their real brands without ingredients (coffee, notebooks, cable, protein
  bars, batteries, ramen, lamp bulb, toothpaste).

So: fragrance (not in #4, tolerated in deodorant/shampoo), SLS and cocamidopropyl betaine (in his
daily shampoo/hand soap/detergent), wool (socks fine; sweater worn after #3 ended), stress (exam weeks
calm except where a flare product overlapped; HRV), dry air (dry days elsewhere calm), travel (#1
only) — all fail. Only MI is in every flare product and in nothing tolerated.

## HRV
Keep `StageStory.hrv(i)` but make the mid-Sep exam week (−26 … −23) dip ~6–8 ms (stress) — including
−23, where scratching is back to normal.

## Calendar
Add: "Trip to Seattle (family)" Aug 24–27 (nights −47 … −44), "Exam week (CS 61B, Math 54 quizzes)"
Sep 14–17 (−26 … −23). Keep midterms, dentist, deadline, CalHacks.

## Tools (Claude)
- scratch_history / weather_history / sleep_history: up to 74 nights (`toolMaxNights = 74`).
- order_history: up to 120 days; each order: date, item, category, bought_before, note, and
  `ingredients` (array) for personal care / household liquids, `material` for clothing/pillow.
- calendar_events: all events in the last N days.
