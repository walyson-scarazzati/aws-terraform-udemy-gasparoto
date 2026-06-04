locals {
  s3_policy = jsondecode(templatefile("${path.module}/policy.json", {
    bucket_name = local.domain
    cdn_oai     = aws_cloudfront_origin_access_identity.this.id
  }))
}

module "logs" {
  source        = "github.com/chgasparoto/terraform-s3-object-notification"
  name          = "${local.domain}-logs"
  acl           = "log-delivery-write"
  force_destroy = !local.has_domain
  tags          = local.common_tags
}

module "website" {
  source        = "github.com/chgasparoto/terraform-s3-object-notification"
  name          = local.domain
  acl           = "private"
  force_destroy = !local.has_domain
  tags          = local.common_tags

  versioning = {
    enabled = true
  }

  filepath = "${local.website_filepath}/build"
  website = {
    index_document = "index.html"
    error_document = "index.html"
  }

  logging = {
    target_bucket = module.logs.name
    target_prefix = "access/"
  }
}

resource "aws_s3_bucket_policy" "website" {
  bucket = module.website.name
  policy = jsonencode(local.s3_policy)
}

module "redirect" {
  source        = "github.com/chgasparoto/terraform-s3-object-notification"
  name          = "www.${local.domain}"
  acl           = "private"
  force_destroy = !local.has_domain
  tags          = local.common_tags

  website = {
    redirect_all_requests_to = local.has_domain ? var.domain : module.website.website
  }
}
