package be.axxes.traineeship.todo.repository;

import be.axxes.traineeship.todo.model.Todo;
import jakarta.enterprise.context.ApplicationScoped;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

@ApplicationScoped
public class InMemoryRepository implements TodoRepository {

    private static final Logger LOGGER = LoggerFactory.getLogger(InMemoryRepository.class);

    private final Map<String, Todo> todos = new HashMap<>();

    @Override
    public List<Todo> getAll() {
        LOGGER.info("Getting all todos");
        return todos.values().stream().toList();
    }

    @Override
    public void create(Todo todo) {
        LOGGER.info("Creating todo: {}", todo.title());
        todos.put(todo.title(), todo);
    }
}
