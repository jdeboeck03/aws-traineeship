package be.axxes.traineeship.todo.repository;

import be.axxes.traineeship.todo.model.Todo;

import java.util.List;

public interface TodoRepository {

    List<Todo> getAll();

    void create(Todo todo);

}
