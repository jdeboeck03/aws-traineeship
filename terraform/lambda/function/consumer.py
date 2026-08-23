import json


def handler(event, context):
    for record in event["Records"]:
        body = json.loads(record["body"])
        # SNS wraps the message in an envelope when delivered via SNS → SQS.
        # Unwrap it so we always work with the original payload.
        if "Message" in body:
            payload = json.loads(body["Message"])
        else:
            payload = body
        print(f"Consumed todo: {payload.get('title', payload)}")
