# Hand the task to another agent

For local agents, install the [portable Agent Display skill](../docs/AGENT-SKILL.md) and ask it to open or move the desired app. For an existing Agent2Agent (A2A) 1.0 receiver, use the example request below. The receiving agent needs access to its user’s logged-in Mac. The desktop app itself stays local.

The fixture uses the A2A 1.0 **HTTP+JSON** binding. Get the receiver’s HTTP+JSON base URL from its Agent Card, supply the authentication that receiver requires, and send a fresh message ID on each new task. From the repository root, for a receiver that accepts requests from your shell:

```sh
python3 -c 'import json,uuid; p=json.load(open("examples/setup-message.json")); p["message"]["messageId"]=str(uuid.uuid4()); print(json.dumps(p))' |
  curl --fail-with-body -X POST "${A2A_BASE_URL%/}/message:send" \
    -H 'A2A-Version: 1.0' -H 'Content-Type: application/a2a+json' \
    --data-binary @-
```

Add the receiver’s required authentication through your usual A2A client or shell configuration. Have that agent return the preview status and the window it moved. An agent without local GUI access should explain what its operator must do on the Mac.

[Agent2Agent v1.0 HTTP examples](https://a2a-protocol.org/v1.0.0/specification/#6-common-workflows-examples)
