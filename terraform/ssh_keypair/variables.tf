
variable "name" {
  description = "Key pair name"
}

variable "tags" {
  type    = map(string)
  default = {}
}