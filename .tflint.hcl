# TFLint configuration shared by all 15 Terraform roots.
#
# Run from the repository root; the validator installs the plugins, passes this
# file to every root, and sets sam_build=true for the three service roots:
#   python3 scripts/validate_infrastructure.py --tflint
#
# Findings that mirror an intentional SAM design are suppressed inline with
# `# tflint-ignore: <rule>` and a reason, matching the cfn-lint serverless-rules
# exclusions (ES4000, ES1001) declared in the SAM templates on `develop`.

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# Serverless Rules: https://awslabs.github.io/serverless-rules/tflint/
plugin "aws-serverless" {
  enabled = true
  version = "0.3.6"
  source  = "github.com/awslabs/serverless-rules"
}

# Plugin 0.3.6 aborts the whole ruleset with "unknown value found" when
# function_name references another resource, which every permission here does.
# Each aws_lambda_permission in this repository grants one literal principal.
rule "aws_lambda_permission_multiple_principals" {
  enabled = false
}
