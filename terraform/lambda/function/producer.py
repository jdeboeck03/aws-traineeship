import json
import os
import random

import boto3

sns = boto3.client("sns")
TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]

TITLES = [
    "Buy milk",
    "Walk the dog",
    "Call the dentist",
    "Read a book",
    "Fix the tests",
    "Write docs",
    "Deploy to prod",
    "Review the PR",
]


def handler(event, context):
    title = random.choice(TITLES)
    sns.publish(TopicArn=TOPIC_ARN, Message=json.dumps({"title": title}))
    print(f"Published todo: {title}")
