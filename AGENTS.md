# Majika Agent Notes

## Recommendation Knowledge

Do not hard-code media-specific knowledge such as title acronyms, franchise aliases,
creator shorthand, or "if the user mentions X, search for Y" dictionaries.

Majika should learn those relationships automatically from the configured model,
service APIs, search tools, user library data, and fetched catalog metadata. When a
query fails, improve the general retrieval, grounding, logging, prompt contract, or
benchmark coverage instead of adding another one-off mapping for a specific game,
show, book, creator, or franchise.

Small deterministic rules are acceptable only when they describe app/service mechanics
or broad structured controls, such as Steam play capabilities, official tag names,
adult-content filters, local co-op wording, stop words, or generic text decomposition.
