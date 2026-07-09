variable "alert_email" {
  description = "Email address subscribed to pipeline failure/success alerts. AWS requires the recipient to click a confirmation link sent to this address before any notifications are actually delivered — subscribing alone is not enough."
  type        = string
}
