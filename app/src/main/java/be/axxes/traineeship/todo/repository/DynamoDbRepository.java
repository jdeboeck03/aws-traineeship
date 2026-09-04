package be.axxes.traineeship.todo.repository;

import be.axxes.traineeship.todo.model.Todo;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.PutItemRequest;
import software.amazon.awssdk.services.dynamodb.model.ScanRequest;
import software.amazon.awssdk.services.dynamodb.model.ScanResponse;

import jakarta.enterprise.context.ApplicationScoped;

import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@ApplicationScoped
public class DynamoDbRepository implements TodoRepository {

    private static final String TABLE_NAME = System.getenv("DYNAMODB_TABLE_NAME");

    private final DynamoDbClient dynamoDbClient;

    public DynamoDbRepository() {
        this.dynamoDbClient = DynamoDbClient.builder()
                .region(Region.EU_WEST_1)
                .build();
    }

    @Override
    public List<Todo> getAll() {
        ScanResponse response = dynamoDbClient.scan(
                ScanRequest.builder().tableName(TABLE_NAME).build());
        return response.items()
                .stream()
                .map(item -> new Todo(item.get("title").s()))
                .collect(Collectors.toList());
    }

    @Override
    public void create(Todo todo) {
        dynamoDbClient.putItem(PutItemRequest.builder()
                .tableName(TABLE_NAME)
                .item(Map.of("title", AttributeValue.fromS(todo.title())))
                .build());
    }
}
