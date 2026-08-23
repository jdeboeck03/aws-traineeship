package be.axxes.traineeship.todo.service;

import be.axxes.traineeship.todo.model.Todo;

import java.util.List;

public interface TodoService {

    List<Todo> getAll();

    void create(Todo todo);

}
