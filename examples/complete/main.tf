## This is the module being used
module "cis_alarms" {
  # Use the git source in your own code
  # source         = "git::https://github.com/cloudposse/terraform-aws-cloudtrail-cloudwatch-alarms.git?ref=<version>"
  source         = "../../"
  log_group_name = aws_cloudwatch_log_group.default.name
}

## Everything after this is standard cloudtrail setup
data "aws_caller_identity" "current" {}

module "label" {
  // https://github.com/cloudposse/terraform-null-label
  source    = "git::https://github.com/cloudposse/terraform-null-label.git?ref=0.19.2"
  namespace = var.namespace
  stage     = var.stage
  name      = var.name
  delimiter = "-"
}

module "cloudtrail_s3_bucket" {
  // https://github.com/cloudposse/terraform-aws-cloudtrail-s3-bucket
  source    = "git::https://github.com/cloudposse/terraform-aws-cloudtrail-s3-bucket.git?ref=0.12.0"
  namespace = var.namespace
  stage     = var.stage
  name      = var.name

}

resource "aws_cloudwatch_log_group" "default" {
  name = module.label.id
  tags = module.label.tags
}

data "aws_iam_policy_document" "log_policy" {
  statement {
    effect  = "Allow"
    actions = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = [
      "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:${aws_cloudwatch_log_group.default.name}:log-stream:*"
    ]
  }
}

data "aws_iam_policy_document" "assume_policy" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      identifiers = ["cloudtrail.amazonaws.com"]
      type        = "Service"
    }
  }
}

resource "aws_iam_role" "cloudtrail_cloudwatch_events_role" {
  name               = lower(join(module.label.delimiter, [module.label.id, "role"]))
  assume_role_policy = data.aws_iam_policy_document.assume_policy.json
  tags               = module.label.tags
}

resource "aws_iam_role_policy" "policy" {
  name   = lower(join(module.label.delimiter, [module.label.id, "policy"]))
  policy = data.aws_iam_policy_document.log_policy.json
  role   = aws_iam_role.cloudtrail_cloudwatch_events_role.id
}

module "cloudtrail" {
  // https://github.com/cloudposse/terraform-aws-cloudtrail
  source                        = "git::https://github.com/cloudposse/terraform-aws-cloudtrail.git?ref=0.14.0"
  namespace                     = var.namespace
  stage                         = var.stage
  name                          = var.name
  enable_log_file_validation    = true
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_logging                = true
  // TODO: Add event_selector
  s3_bucket_name = module.cloudtrail_s3_bucket.bucket_id
  // https://github.com/terraform-providers/terraform-provider-aws/issues/14557#issuecomment-671975672
  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.default.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_cloudwatch_events_role.arn
}


## Remap the outputs for testing

output "sns_topic_arn" {
  value = module.cis_alarms.sns_topic_arn
}

output "dashboard_individual" {
  value = module.cis_alarms.dashboard_individual
}

output "dashboard_combined" {
  value = module.cis_alarms.dashboard_combined
}