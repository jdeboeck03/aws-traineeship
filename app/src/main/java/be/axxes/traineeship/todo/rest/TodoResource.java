package be.axxes.traineeship.todo.rest;

import be.axxes.traineeship.todo.model.Todo;
import be.axxes.traineeship.todo.service.TodoService;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

import java.util.List;

@Path("/todo")
public class TodoResource {

    private final TodoService service;

    public TodoResource(TodoService service) {
        this.service = service;
    }

    @GET
    @Produces(MediaType.APPLICATION_JSON)
    public List<Todo> getTodos() {
        return service.getAll();
    }

    @POST
    @Consumes(MediaType.APPLICATION_JSON)
    public Response create(Todo todo) {
        service.create(todo);
        return Response.accepted().build();
    }
}
