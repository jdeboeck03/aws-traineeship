package be.axxes.traineeship.todo.service;

import be.axxes.traineeship.todo.model.Todo;
import jakarta.enterprise.context.ApplicationScoped;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.sns.SnsClient;

@ApplicationScoped
public class TodoCreatedListener {

    private static final Logger LOGGER = LoggerFactory.getLogger(TodoCreatedListener.class);

    private static final String TOPIC_ARN = System.getenv("SNS_TOPIC_ARN");

    private final SnsClient snsClient;

    public TodoCreatedListener() {
        this.snsClient = SnsClient.builder()
                .region(Region.EU_WEST_1)
                .build();
    }

    public void onCreated(Todo todo) {
        LOGGER.info("Todo created: {}", todo.title());
        // TODO: publish to SNS
        // snsClient.publish(builder -> builder
        //         .topicArn(TOPIC_ARN)
        //         .message(todo.title())
        //         .build());
    }
}
