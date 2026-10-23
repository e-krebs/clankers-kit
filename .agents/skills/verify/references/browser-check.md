# Browser pass

Read this when step 3 runs, which happens when the profile has a Browser check row and the plan's
Gates row or its brief calls for a browser pass, or when the user asked for one.

The Browser check row holds `<dir>: <dev server command> → <base URL>`. Start that server as a
background Bash call with its output redirected to `<scratchpad>/verify-server.log`, and take
the page path from the plan.

Classify the change from the plan:

- Behavioral (handlers, hooks, API calls, state, endpoints): exercise the changed interaction,
  then read the network requests and the console through the browser tooling the session offers.
  Filter the network list to the requests the change touches rather than reading it whole.
  A screenshot alone is not a verdict here.
- Pure-visual (copy, classNames, layout): a screenshot, checked against the change the plan
  describes. No network or console sweep.

The verdict is passed when the observed behavior or appearance matches the plan, failed with the
mismatch stated otherwise. With no browser tooling in the session, record the pass as blocked and
say why. Stop the dev server once the verdict is in.
