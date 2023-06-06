output "key_name" {
  value = aws_key_pair.generated.key_name
}

output "private_key" {
  value = aws_secretsmanager_secret_version.pem.secret_string
}

output "public_key" {
  value = aws_key_pair.generated.public_key
}