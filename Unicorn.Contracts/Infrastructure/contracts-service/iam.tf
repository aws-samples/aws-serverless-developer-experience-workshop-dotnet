resource "aws_iam_role_policy_attachment" "contract_event_handler_xray" {
  role       = aws_iam_role.contract_event_handler_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AWSXRayDaemonWriteAccess"
}








