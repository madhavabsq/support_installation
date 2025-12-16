import json
import boto3
import logging
import datetime
from botocore.exceptions import ClientError

# ========= CONFIG (INLINE, NOT FROM LAMBDA ENV) ======== #
APPLICATION_NAME      = "BSQ-FINALYZER-NONPROD"
UPGRADE_TAG_KEY       = "auto-upgrade"
UPGRADE_INSTANCE_TYPE = "r6a.large"
DEGRADE_TAG_KEY       = "auto-degrade"
DEGRADE_INSTANCE_TYPE = "t3a.nano"
S3_LOG_BUCKET         = "finalyzer-nonprod-lambda-logs"
S3_LOG_KEY_PREFIX     = "eb_downgrade-upgrade_logs"

# ========= LOGGING SETUP ======== #
# Setting INFO level
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Empty List for Storing All Log Lines
log_lines = []

# Create new Class inheriting the Class logging.Handler
class MemLogHandler(logging.Handler):
    """
    A custom logging handler that stores log records in a list in memory.
    This is used to capture all log output before uploading it to S3.
    """
    # Input Params: self = reference to MemLogHanlder object | record = LogRecord object
    def emit(self, record):
        log_entry = self.format(record)
        log_lines.append(log_entry)

# ========= INITIALIZE ELASTIC BEANSTALK CLIENT ONCE ========== #
eb_client = boto3.client('elasticbeanstalk', region_name='ap-south-1')

# >>>>>>>>>>>>>> S3 PUT OBJECT <<<<<<<<<<<<<<<< #
# Input Params: bucket = string | key = string | log_data = bytes | file_description = string w File ~ default value
def upload_logs_to_s3(bucket: str, key: str, log_data: bytes, file_description: str = "File"):
    # Initialize the boto3 s3 client
    s3 = boto3.client("s3")
    try:
        # put_object API call with Attributes: Bucket | Key | Body
        s3.put_object(Bucket=bucket, Key=key, Body=log_data)
        logger.info(f"{file_description} uploaded to s3://{bucket}/{key}")
    # ClientError exception allows the code to catch a specific type of error related to the AWS client
    except ClientError as e:
        logger.error(f"Failed to upload {file_description} to S3: {e}")

# >>>>>>>>>>>>>>>> FIND ENVIRONMENTS (w/ tags + current type) <<<<<<<<<<<<<<<<<<<<<< #
# Input Params: application_name = string | upgrade_tag_key = string | degrade_tag_key = string)
def find_tagged_environments(application_name: str, upgrade_tag_key = None, degrade_tag_key = None):
    environments_to_process = []
    try:
        # (1) --- List all environments --- #
        env_resp = eb_client.describe_environments(
            ApplicationName=application_name,
            IncludeDeleted=False
        )

        for environment in env_resp.get("Environments", []):
            env_name = environment["EnvironmentName"]
            env_arn  = environment["EnvironmentArn"]

            # (2) --- Fetch tags --- #
            tags_response = eb_client.list_tags_for_resource(ResourceArn=env_arn)
            tags = {}
            for tag in tags_response.get("ResourceTags", []):
                key, val = tag.get("Key"), tag.get("Value")
                if key:
                    tags[key] = val

            # (2.1) Filtering : must have at least auto-upgrade/auto-degrade tag set to 'true'
            has_upgrade_true = False
            has_degrade_true = False
            if upgrade_tag_key:
                has_upgrade_true = str(tags.get(upgrade_tag_key, "")).strip().lower() == "true"
            if degrade_tag_key:
                has_degrade_true = str(tags.get(degrade_tag_key, "")).strip().lower() == "true"

            # If neither required tag is present as 'true', skip this env
            if not (has_upgrade_true or has_degrade_true):
                continue

            # (3) --- Fetch current instance type --- #
            current_instance_type = None
            try:
                config_settings = eb_client.describe_configuration_settings(
                    ApplicationName=application_name,
                    EnvironmentName=env_name
                )
                for setting in config_settings.get("ConfigurationSettings", []):
                    for option in setting.get("OptionSettings", []):
                        if (
                            option.get("Namespace") == "aws:autoscaling:launchconfiguration"
                            and option.get("OptionName") == "InstanceType"
                        ):
                            current_instance_type = option.get("Value")
                            break
            except ClientError as e:
                logger.error(f"AWS Client Error getting instance type for {env_name}: {e}")
            except Exception as e:
                logger.error(f"Couldn't fetch instance type for {env_name}: {e}")

            environments_to_process.append({
                'name': env_name,
                'arn': env_arn,
                'tags': tags,
                'current_instance_type': current_instance_type
            })

    except ClientError as e:
        logger.error(f"AWS Client Error describing environments: {e}")
    except Exception as e:
        logger.error(f"Error while trying to list environments: {e}")

    return environments_to_process

# >>>>>>>>>>>>>>> UPGRADE ENVIRONMENT (tag-gated) <<<<<<<<<<<<<<< #
# Input Params: environment = dict | application_name = string | tag_key = string | target_type = string
def initiate_eb_environment_upgrade(environment: dict, application_name: str, tag_key: str, target_type: str):
    # env_name, tags & current is taken from the "name" | "tags" | "current_instance_type" key we set in results list returned from 
    # find_tagged_environments to hold the EnvironmentName string
    env_name = environment["name"]
    tags = environment.get("tags", {})
    current = environment.get("current_instance_type")

    # If auto-upgrade key is empty/unset
    if not tag_key:
        logger.info(f"[UPGRADE] {env_name}: no tag key configured; skipping.")
        return False
    
    # If auto-upgrade not explicitly "true" then Skip
    if str(tags.get(tag_key, "")).strip().lower() != "true":
        logger.info(f"[UPGRADE] {env_name}: tag {tag_key} != 'true'; skipping.")
        return False

    # If UPGRADE_INSTANCE_TYPE = r6a.large already then Skip
    if current == target_type:
        logger.info(f"[UPGRADE] {env_name}: already {current}; skipping.")
        return False

    try:
        # update-environment API Call with Attributes: ApplicationName | EnvironmentName & OptionSettings
        eb_client.update_environment(
            ApplicationName=application_name,
            EnvironmentName=env_name,
            OptionSettings=[{
                "Namespace": "aws:autoscaling:launchconfiguration",
                "OptionName": "InstanceType",
                "Value": target_type
            }]
        )
        logger.info(f"[UPGRADE] Update sent for {env_name} -> {target_type}")
        return True
    except ClientError as e:
        logger.error(f"[UPGRADE] AWS Client Error for {env_name}: {e}")
    except Exception as e:
        logger.error(f"[UPGRADE] Unexpected error for {env_name}: {e}")
    return False

# >>>>>>>>>>>>>>> DOWNGRADE ENVIRONMENT (tag-gated) <<<<<<<<<<<<<<< #
# Input Params: environment = dict | application_name = string | tag_key = string | target_type = string
def initiate_eb_environment_downgrade(environment: dict, application_name: str, tag_key: str, target_type: str):
    env_name = environment["name"]
    tags = environment.get("tags", {})
    current = environment.get("current_instance_type")

    if not tag_key:
        logger.info(f"[DOWNGRADE] {env_name}: no tag key configured; skipping.")
        return False

    if str(tags.get(tag_key, "")).strip().lower() != "true":
        logger.info(f"[DOWNGRADE] {env_name}: tag {tag_key} != 'true'; skipping.")
        return False

    if current == target_type:
        logger.info(f"[DOWNGRADE] {env_name}: already {current}; skipping.")
        return False

    try:
        eb_client.update_environment(
            ApplicationName=application_name,
            EnvironmentName=env_name,
            OptionSettings=[{
                "Namespace": "aws:autoscaling:launchconfiguration",
                "OptionName": "InstanceType",
                "Value": target_type
            }]
        )
        logger.info(f"[DOWNGRADE] Update sent for {env_name} -> {target_type}")
        return True
    except ClientError as e:
        logger.error(f"[DOWNGRADE] AWS Client Error for {env_name}: {e}")
    except Exception as e:
        logger.error(f"[DOWNGRADE] Unexpected error for {env_name}: {e}")
    return False

def lambda_handler(event, context):
    mem_handler = MemLogHandler()
    logger.addHandler(mem_handler)

    # Use inline config directly (no os.environ lookups)
    application_name      = APPLICATION_NAME
    s3_log_bucket         = S3_LOG_BUCKET
    s3_log_key_prefix     = S3_LOG_KEY_PREFIX
    upgrade_tag_key       = UPGRADE_TAG_KEY
    upgrade_instance_type = UPGRADE_INSTANCE_TYPE
    degrade_tag_key       = DEGRADE_TAG_KEY
    degrade_instance_type = DEGRADE_INSTANCE_TYPE

    # EventBridge constant input: {"mode":"upgrade"} or {"mode":"downgrade"}
    mode = (event or {}).get("mode")
    logger.info(f"Starting EB updates. mode={mode!r}")

    try:
        if mode == "upgrade":
            envs = find_tagged_environments(application_name, upgrade_tag_key=upgrade_tag_key)
            for env in envs:
                if upgrade_tag_key and upgrade_instance_type:
                    initiate_eb_environment_upgrade(env, application_name, upgrade_tag_key, upgrade_instance_type)

        elif mode == "downgrade":
            envs = find_tagged_environments(application_name, degrade_tag_key=degrade_tag_key)
            for env in envs:
                if degrade_tag_key and degrade_instance_type:
                    initiate_eb_environment_downgrade(env, application_name, degrade_tag_key, degrade_instance_type)

        else:
            envs = find_tagged_environments(application_name,
                                            upgrade_tag_key=upgrade_tag_key,
                                            degrade_tag_key=degrade_tag_key)
            for env in envs:
                did_upgrade = False
                if upgrade_tag_key and upgrade_instance_type:
                    did_upgrade = initiate_eb_environment_upgrade(env, application_name, upgrade_tag_key, upgrade_instance_type)
                if not did_upgrade and degrade_tag_key and degrade_instance_type:
                    initiate_eb_environment_downgrade(env, application_name, degrade_tag_key, degrade_instance_type)

        logger.info("All applicable update commands have been sent. Lambda will now exit.")

    except Exception as e:
        logger.error(f"Something unexpected happened during execution: {e}")
        raise
    finally:
        all_log_output = "\n".join(log_lines).encode("utf-8")
        now = datetime.datetime.now()
        ts = now.strftime("%H-%M-%S")
        dated_key  = f"{s3_log_key_prefix}/archived/{now.strftime('%Y/%m/%d')}/beanstalk-combined-{ts}-{context.aws_request_id}.log"
        latest_key = f"{s3_log_key_prefix}/latest/beanstalk-combined-latest.log"
        upload_logs_to_s3(s3_log_bucket, dated_key, all_log_output, "Archived Log")
        upload_logs_to_s3(s3_log_bucket, latest_key, all_log_output, "Latest Log")
        # Remove Custom Class mem_handler from Lambda runtime memory
        logger.removeHandler(mem_handler)

    return {"statusCode": 200, "body": json.dumps("Commands sent. Check the EB console and S3 logs for details.")}