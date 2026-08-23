package be.axxes.traineeship.todo.service;

import be.axxes.traineeship.todo.model.Todo;
import be.axxes.traineeship.todo.repository.TodoRepository;
import jakarta.enterprise.context.ApplicationScoped;

import java.util.List;

@ApplicationScoped
public class TodoServiceImpl implements TodoService {

    private final TodoRepository repository;
    private final TodoCreatedListener listener;

    public TodoServiceImpl(TodoRepository repository, TodoCreatedListener listener) {
        this.repository = repository;
        this.listener = listener;
    }

    @Override
    public List<Todo> getAll() {
        return repository.getAll();
    }

    @Override
    public void create(Todo todo) {
        repository.create(todo);
        listener.onCreated(todo);
    }
}
