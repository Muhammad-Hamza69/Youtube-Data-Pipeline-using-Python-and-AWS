variable "youtube_api_key" {
  description = "The existing YouTube Data API v3 key (kept as-is per project decision — not rotated). Passed via -var, never committed to a .tf/.tfvars file."
  type        = string
  sensitive   = true
}
