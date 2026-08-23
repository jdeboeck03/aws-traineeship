output "producer_function_name" {
  description = "Name of the scheduled producer Lambda function."
  value       = aws_lambda_function.producer.function_name
}

output "consumer_function_name" {
  description = "Name of the SQS consumer Lambda function."
  value       = aws_lambda_function.consumer.function_name
}
