# SE Workshop Methodology — Reusable Template

A structured approach for Sales Engineers to design and deliver hands-on technical workshops for customers.

---

## 1. Brief the client

| Question | Why it matters |
|----------|---------------|
| What's the use case? | The workshop must solve a real problem they recognize |
| What's the technical blocker? | Design the workshop to address it head-on |
| Who are the participants? | Dev? Analyst? Manager? Drives tool choices and depth |
| How many people will code? | 1 = pair-programming. 3+ = follow-along with checkpoints |
| What's their current stack? | Draw explicit parallels with Snowflake equivalents |
| Do they have a Snowflake account? | Their account (stickier) vs. demo account (cleaner) |

**Output:** A one-paragraph scenario description.

## 2. Design the scenario

- **Use their real data** (sample) when possible — results are immediately meaningful
- **Follow their real architecture** — same table names, same pipeline steps
- **Scope to what fits in 2-3 hours** — core steps only, extras as optional modules
- **Each step produces a tangible output** — a table, a UDF, a view

## 3. Scope: day-of vs. bonus

| Day-of (hands-on) | 3-4 blocks, participants build live |
| Bonus (in repo) | Extra modules, same quality, for self-study |
| Buffer | One bonus module you can pull in if ahead |

Plan for 80% of your time slot. The rest goes to questions and setup issues.

## 4. Match tools to audience

| Developers | Snow CLI + Notebooks |
| Analysts | Snowsight worksheets |
| Mixed | Notebooks (SQL + Python cells) |
| Executives | Streamlit app + live demo |

## 5. Structure the agenda

Each block: 5 min explain → 15-30 min build together → 5 min verify.

- Setup: 15-20 min
- Core blocks: 25-45 min each
- Wrap-up: 15 min minimum
- Total: 2-3 hours

## 6. Build the support

- **Repo Git:** one folder per step, each with README + SQL/Python files
- **Notebook:** interactive mirror of the repo steps
- **Prerequisites email:** send 1 week before with install commands
- **Data files:** CSV/JSON in a `data/` folder

## 7. Deliver

**Before:** test end-to-end on target account, pre-create ACCOUNTADMIN objects.
**During:** start with briefing, go slow on setup, verify after each block.
**After:** send repo link, summary of what was built, and next steps.

## 8. Checklist

- [ ] Client brief completed
- [ ] Scenario designed with real data and real table names
- [ ] Sample data extracted
- [ ] Day-of vs. bonus scope defined
- [ ] Repo + notebook created
- [ ] Prerequisites email sent
- [ ] End-to-end test passed
- [ ] Fallback plan ready (pre-computed results if APIs fail)
