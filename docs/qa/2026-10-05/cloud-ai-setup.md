# Cloud AI setup and compatibility

Settings now offers **Set up free cloud AI**, which selects OpenRouter's free router and fills the endpoint/model. Existing Gemini, Groq, custom OpenAI-compatible, and manual copy/paste modes remain available. Built-in endpoints are under Advanced connection settings.

Provider-specific instructions explain account creation, API keys, free-tier eligibility, and provider-side spending controls. A free-tier model name does not guarantee free usage on a paid account. The built-in OpenRouter preset sends `provider.max_price` of zero for prompt, completion and request charges, with `require_parameters: true`, in inference, tool rounds, empty-response retries, and the setup probe. Custom-provider billing is not controlled by this preset.

The user-initiated capability test makes at most three synthetic requests with 256 output tokens each. It checks exact JSON instruction following, a function call with valid arguments, and use of an unpredictable value returned through a tool message. It never sends the user's library or runs catalog/web tools. It reports actionable errors without displaying raw provider response bodies. Editing the key, model, endpoint or provider cancels and invalidates results. Results are session-only and do not alter model trust tiers; a pass is basic protocol compatibility, not evidence of recommendation quality or context capacity. Free routers may select a different model on later calls.

Live provider tests require a user-supplied key. Automated tests use mocked HTTP and cover success, malformed JSON, missing tool support, fabricated tool results, missing credentials, insecure endpoint rejection, auth/quota/credit errors, timeout, price ceilings, setup navigation, and stale result invalidation.

Provider documentation checked for this change:

- [Gemini billing and free/paid tiers](https://ai.google.dev/gemini-api/docs/billing)
- [Groq spend limits and tracking delay](https://console.groq.com/docs/spend-limits)
- [OpenRouter free variants and availability](https://openrouter.ai/docs/guides/routing/model-variants/free)
- [OpenRouter routing and maximum prices](https://openrouter.ai/docs/guides/routing/provider-selection)
- [OpenRouter key limits](https://openrouter.ai/docs/api-reference/limits)

No fixed dollar prices or quota counts are embedded; users can follow the current provider documentation from Settings.
