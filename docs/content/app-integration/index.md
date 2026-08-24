# Create and Connect the App

The Quarkus app in `app/` already contains all the AWS SDK code — it just needs to be activated.
The SDK authenticates via the ECS task role automatically; no access keys are needed anywhere in
the code or configuration.

## DynamoDB

Open `app/src/main/java/.../repository/DynamoDbRepository.java`.

Uncomment `@ApplicationScoped` on `DynamoDbRepository` and remove it from `InMemoryRepository`.
The table name is read from the `DYNAMODB_TABLE_NAME` environment variable, which the ECS task
definition already injects.

## SNS — publishing

Open `app/src/main/java/.../service/TodoCreatedListener.java`.

Uncomment the `snsClient.publish(...)` block inside `onCreated`. Every todo creation will now
publish a message to the SNS topic, which fans out to the subscribed SQS queue.

## SQS — consuming

Open `app/src/main/java/.../service/QueueConsumer.java`.

Uncomment `@ApplicationScoped` and `@Scheduled(every = "10s")`. The consumer polls the queue
every 10 seconds, logs each message, and deletes it after processing.
