package be.axxes.traineeship.todo.service;

import be.axxes.traineeship.todo.model.Todo;
import jakarta.enterprise.context.ApplicationScoped;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;

@ApplicationScoped
public class S3BackupListener {

    private static final String BUCKET_NAME = System.getenv("S3_BUCKET_NAME");

    private final S3Client s3Client;

    public S3BackupListener() {
        this.s3Client = S3Client.builder()
                .region(Region.EU_WEST_1)
                .build();
    }

    public void onCreated(Todo todo) {
        // Uncomment to back up each new todo to S3 as a JSON object.
        // String key = "todos/" + System.currentTimeMillis() + ".json";
        // s3Client.putObject(
        //         PutObjectRequest.builder()
        //                 .bucket(BUCKET_NAME)
        //                 .key(key)
        //                 .contentType("application/json")
        //                 .build(),
        //         RequestBody.fromString("{\"title\":\"" + todo.title() + "\"}"));
    }
}
