resource "aws_s3_bucket" "this" {
  bucket = var.name
  tags   = var.tags

  dynamic "versioning" {
    for_each = length(keys(var.versioning)) == 0 ? [] : [var.versioning]
    content {
      enabled    = lookup(versioning.value, "enabled", null)
      mfa_delete = lookup(versioning.value, "mfa_delete", null)
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  count = var.policy != null ? 1 : 0

  bucket = aws_s3_bucket.this.id
  policy = var.policy
}

resource "aws_s3_bucket_website_configuration" "this" {
  count = length(keys(var.website)) == 0 ? 0 : 1

  bucket = aws_s3_bucket.this.id

  dynamic "index_document" {
    for_each = lookup(var.website, "index_document", null) == null ? [] : [1]
    content {
      suffix = var.website["index_document"]
    }
  }

  dynamic "error_document" {
    for_each = lookup(var.website, "error_document", null) == null ? [] : [1]
    content {
      key = var.website["error_document"]
    }
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = var.acl != "public-read" ? true : false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }

  depends_on = [aws_s3_bucket_public_access_block.this]
}

resource "aws_s3_bucket_acl" "this" {
  bucket = aws_s3_bucket.this.id
  acl    = var.acl

  depends_on = [aws_s3_bucket_ownership_controls.this]
}

module "objects" {
  source = "./s3_object"

  for_each = var.files != "" ? fileset(var.files, "**") : []

  bucket = aws_s3_bucket.this.bucket
  key    = "${var.key_prefix}/${each.value}"
  src    = "${var.files}/${each.value}"
}
