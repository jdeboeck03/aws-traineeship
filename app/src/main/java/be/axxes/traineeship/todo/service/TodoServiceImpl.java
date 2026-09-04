package be.axxes.traineeship.todo.service;

import be.axxes.traineeship.todo.model.Todo;
import be.axxes.traineeship.todo.repository.TodoRepository;
import jakarta.enterprise.context.ApplicationScoped;

import java.util.List;

@ApplicationScoped
public class TodoServiceImpl implements TodoService {

    private final TodoRepository repository;
    private final TodoCreatedListener listener;
    private final S3BackupListener s3Backup;

    public TodoServiceImpl(TodoRepository repository, TodoCreatedListener listener, S3BackupListener s3Backup) {
        this.repository = repository;
        this.listener = listener;
        this.s3Backup = s3Backup;
    }

    @Override
    public List<Todo> getAll() {
        return repository.getAll();
    }

    @Override
    public void create(Todo todo) {
        repository.create(todo);
        listener.onCreated(todo);
        s3Backup.onCreated(todo);
    }
}
