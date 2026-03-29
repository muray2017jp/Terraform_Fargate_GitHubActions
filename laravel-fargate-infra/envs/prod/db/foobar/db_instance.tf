# 1. パスワードをランダム生成（16文字、特殊文字なしで安全性を確保）
resource "random_password" "db_password" {
  length           = 16
  special          = false
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# 2. 生成したパスワードをパラメータストア(SSM)に保存
resource "aws_ssm_parameter" "db_password" {
  name  = "/${local.system_name}/${local.env_name}/${local.service_name}/DB_PASSWORD"
  type  = "SecureString" # 暗号化して保存（標準パラメータなのでストレージ無料）
  value = random_password.db_password.result

  tags = {
    Name = "${local.system_name}-${local.env_name}-${local.service_name}-db-password"
  }
}

resource "aws_db_instance" "this" {
  # Engine options
  engine         = "mysql"
  engine_version = "8.0"

  # Settings
  identifier = "${local.system_name}-${local.env_name}-${local.service_name}"

  # Credentials Settings
  username = local.service_name
  # 修正箇所: ハードコードを廃止し、生成されたパスワードを参照
  password = random_password.db_password.result

  # DB instance class
  instance_class = "db.t3.micro"

  # Storage
  storage_type          = "gp3"
  allocated_storage     = 20
  max_allocated_storage = 0

  # Availability & durability
  multi_az = false

  # Connectivity
  db_subnet_group_name = data.terraform_remote_state.network_main.outputs.db_subnet_group_this_id
  publicly_accessible  = false
  vpc_security_group_ids = [
    data.terraform_remote_state.network_main.outputs.security_group_db_foobar_id,
  ]
  availability_zone = "ap-northeast-1a"
  port              = 3306

  # Database authentication
  iam_database_authentication_enabled = false

  # Database options
  db_name              = local.service_name
  parameter_group_name = aws_db_parameter_group.this.name
  option_group_name    = aws_db_option_group.this.name

  # Backup
  backup_retention_period  = 1
  backup_window            = "17:00-18:00"
  copy_tags_to_snapshot    = true
  delete_automated_backups = true
  skip_final_snapshot      = true

  # Encryption
  storage_encrypted = true
  kms_key_id        = data.aws_kms_alias.rds.target_key_arn

  # Performance Insights (db.t3.micro, db.t3.small are not supported)
  performance_insights_enabled = false

  # Monitoring
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring_role.arn

  # Log exports
  enabled_cloudwatch_logs_exports = [
    "error",
    "general",
    "slowquery"
  ]

  # Maintenance
  auto_minor_version_upgrade = false
  maintenance_window         = "fri:18:00-fri:19:00"

  # Deletion protection
  deletion_protection = false

  tags = {
    Name = "${local.system_name}-${local.env_name}-${local.service_name}"
  }
}

resource "aws_ssm_parameter" "db_host" {
  name  = "/${local.system_name}/${local.env_name}/${local.service_name}/DB_HOST"
  type  = "String"
  value = aws_db_instance.this.address
}