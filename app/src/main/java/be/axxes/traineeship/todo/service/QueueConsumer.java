package be.axxes.traineeship.todo.service;

import jakarta.enterprise.context.ApplicationScoped;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.sqs.SqsClient;
import software.amazon.awssdk.services.sqs.model.ReceiveMessageResponse;

// Uncomment @ApplicationScoped to activate the queue consumer.
// @ApplicationScoped
public class QueueConsumer {

    private static final Logger LOGGER = LoggerFactory.getLogger(QueueConsumer.class);

    private static final String QUEUE_URL = System.getenv("SQS_QUEUE_URL");

    private final SqsClient sqsClient;

    public QueueConsumer() {
        this.sqsClient = SqsClient.builder()
                .region(Region.EU_WEST_1)
                .build();
    }

    // @Scheduled(every = "10s")
    public void consume() {
        ReceiveMessageResponse response = sqsClient.receiveMessage(
                builder -> builder.queueUrl(QUEUE_URL));
        response.messages().forEach(message -> {
            LOGGER.info("Received: {}", message.body());
            sqsClient.deleteMessage(builder -> builder
                    .queueUrl(QUEUE_URL)
                    .receiptHandle(message.receiptHandle())
                    .build());
        });
    }
}
