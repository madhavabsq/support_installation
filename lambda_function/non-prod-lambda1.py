"""
AWS Lambda Function: EC2 Auto Start/Stop
This Lambda function automatically starts and stops EC2 instances based on tags and scheduled times.
- Auto-Stop: Triggers at 14:00 UTC (8:00 PM IST) for instances tagged for auto-stop
- Auto-Start: Triggers at 02:00 UTC (8:00 AM IST) for instances tagged for auto-start
Logs are stored in an S3 bucket for audit and troubleshooting purposes.
"""

import json
import boto3
import logging
import time

# Configure logging for CloudWatch Logs
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Global list to store log messages that will be written to S3
text_file_content = []

# Tag key names used to identify instances for auto-start/stop
# Replace <key_name> with your actual tag keys (e.g., 'AutoStart', 'AutoStop')
autostart_tag = 'tag:CNTRL-START'
autostop_tag = 'tag:CNTRL-STOP'

def get_tagged_ec2_instances_by_state(ec2_state_flag):
    
    """
    Retrieves EC2 instances based on their state and appropriate tags.
    
    Args:
        ec2_state_flag (str): The desired instance state ('running' or 'stopped')
    
    Returns:
        dict: AWS API response containing list of instances matching the filters
    
    Logic:
        - If looking for 'running' instances, use autostop_tag (to stop running instances)
        - If looking for 'stopped' instances, use autostart_tag (to start stopped instances)
    """
    
    # Determine which tag to use based on the current state
    if ec2_state_flag == 'running':
        target_tag_key = autostop_tag
    elif ec2_state_flag == 'stopped':
        target_tag_key = autostart_tag
        
        
    # Create EC2 client to interact with AWS EC2 service
    aws_ec2_client_bsq = boto3.client('ec2')

    # Query EC2 instances with filters for 
    # 1) tag value  AND
    # 2) instance state
    ec2_describe_instances_result = aws_ec2_client_bsq.describe_instances(
        Filters=[
            {
                'Name': target_tag_key,
                'Values': ['true','True']
            },
            {
                'Name': 'instance-state-name',
                'Values': [ec2_state_flag]
            }
        ]
    )
    return ec2_describe_instances_result

    
def stop_single_ec2_instance(instance_id):

    """
    Attempts to stop a single EC2 instance.
    
    Args:
        instance_id (str): The EC2 instance ID to stop
    
    Returns:
        bool: True if stop command was successful, False if an error occurred
    
    Side Effects:
        - Logs to CloudWatch and text_file_content list
        - Sends stop command to AWS EC2 service
    """

    aws_ec2_client_bsq = boto3.client('ec2')
    try:
        # Send stop command to the EC2 instance
        ec2_stop_result = aws_ec2_client_bsq.stop_instances(
            InstanceIds=[
                instance_id
            ]
        )

        # Log success
        logger.info('ATTEMPTING STOP ON INSTANCE ID :' + instance_id)
        text_append(text_file_content, 'ATTEMPTING STOP ON INSTANCE ID :' + instance_id, '[INFO]')
        return True

    except Exception as e:
        # Log detailed error information if STOP fails
        error_message = f'ERROR STOPPING INSTANCE ID : {instance_id} | Exception: {str(e)}'
        logger.error(error_message)
        logger.error('ERROR STOPPING INSTANCE ID :' + instance_id)
        text_append(text_file_content, 'ERROR STOPPING INSTANCE ID :' + instance_id, '[ERROR]')
        text_append(text_file_content, error_message, '[ERROR]')
        return False

def start_single_ec2_instance(instance_id):
    
    """
    Attempts to start a single EC2 instance.
    
    Args:
        instance_id (str): The EC2 instance ID to start
    
    Returns:
        dict: AWS API response from the start_instances call, or None on error
    
    Side Effects:
        - Logs to CloudWatch and text_file_content list
        - Sends start command to AWS EC2 service
    """
    
    aws_ec2_client_bsq = boto3.client('ec2')
    try:
        # Send start command to the EC2 instance
        ec2_start_result = aws_ec2_client_bsq.start_instances(
            InstanceIds=[
                instance_id
            ]
        )
        # Log success
        logger.info('ATTEMPTING START ON INSTANCE ID :' + instance_id)
        text_append(text_file_content, 'ATTEMPTING START ON INSTANCE ID :' + instance_id, '[INFO]')
        return ec2_start_result

    except Exception as e:
        # Log detailed error information if START fails
        error_message = f'ERROR STARTING INSTANCE ID : {instance_id} | Exception: {str(e)}'
        logger.error('ERROR STARTING INSTANCE ID :' + instance_id)
        logger.error(error_message)
        text_append(text_file_content, 'ERROR STARTING INSTANCE ID :' + instance_id, '[ERROR]')
        text_append(text_file_content, error_message, '[ERROR]')

def instance_name_from_id (reference_id):
    
    """
    Retrieves the 'Name' tag value of an EC2 instance.
    
    Args:
        reference_id (str): The EC2 instance ID
    
    Returns:
        str: The instance name (value of 'Name' tag), or None if not found
    
    Purpose:
        Makes logs more human-readable by showing instance names instead of just IDs
    """

    aws_ec2_client_bsq = boto3.client('ec2')
    
    # Get instance details
    response = aws_ec2_client_bsq.describe_instances(
        InstanceIds=[
            reference_id
        ]
    )
   
    # Search through the response structure to find the 'Name' tag
    for reservation in response['Reservations']:
        for instance in reservation['Instances']:
            for tag in instance['Tags']:
                if tag['Key'] == 'Name':
                    return tag['Value']


def log_refreshed_instance_state(instance,new_state):
    
    """
    Logs the current state of an instance and warns about critical states.
    
    Args:
        instance (dict): The instance object from AWS API response
        new_state (str): The current state of the instance
    
    Side Effects:
        - Logs instance state changes
        - Issues warnings for transitional states (pending, stopping)
        - Issues critical alerts for termination states
    """
    
    # Find the instance name from tags
    for tag in instance['Tags']:
            if tag['Key'] == 'Name':
                logger.info('New State :' + new_state + ', INSTANCE NAME :' + tag['Value'])
                text_append(text_file_content, 'New State :' + new_state + ', INSTANCE NAME :' + tag['Value'], '[INFO]')
                if new_state == 'pending' or new_state == 'stopping':
                    logger.warning('It is not recommended to interupt this instance state by rerunning the Lambda---> ' + new_state)
                    text_append(text_file_content, 'It is not recommended to interupt this instance state by rerunning the Lambda---> ' + new_state, '[WARNING]')
                if new_state == 'shutting-down':
                    logger.critical('This instance is in getting terminated state. Kindly address this to the Infra Admin' + new_state, '[INFO]')
                    text_append(text_file_content, 'This instance is in getting terminated state. Kindly address this to the Infra Admin' + new_state, '[CRITICAL]')

def refresh_instance_state(reference_id, confirm_action = True):
    
    """
    Retrieves the current state of an EC2 instance.
    
    Args:
        reference_id (str): The EC2 instance ID
        confirm_action (bool): Flag to confirm if action should proceed (default: True)
    
    Returns:
        str: The current state of the instance ('running', 'stopped', 'pending', etc.)
             or 'Instance Not Found' if instance doesn't exist
             or 'This instance cannot be stopped' if confirm_action is False
    
    Note:
        This function refreshes the instance state by making a new API call,
        ensuring we have the latest status information.
    """
    
    # Safety check - return early if action is not confirmed
    if confirm_action == False:
        return 'This instance cannot be stopped '
    else:
        aws_ec2_client_bsq = boto3.client('ec2') 
        
        # Get all instances (Note: This could be optimized to filter by instance ID)
        refreshed_response = aws_ec2_client_bsq.describe_instances()
        check_flag = -1

        for reservation in refreshed_response['Reservations']:
            for instance in reservation['Instances']:
                if instance['InstanceId'] == reference_id:
                    check_flag = 0
                    return instance['State']['Name']
                    break
            if check_flag == 0:
                break
        if check_flag == -1:
            return 'Instance Not Found'

def text_append(text_file_content, text, log_level):
    
    """
    Appends a formatted log entry to the text file content list.
    
    Args:
        text_file_content (list): List to store log entries
        text (str): The log message
        log_level (str): Log level indicator (e.g., '[INFO]', '[ERROR]', '[WARNING]')
    
    Returns:
        list: Updated text_file_content list
    
    Format:
        [LOG_LEVEL]  [Timestamp] Message
    """
    
    text_file_content.append(log_level + '  [' + time.ctime() +'] '+ text)
    return text_file_content

def text_file_commit(text_file_content):
    
    """
    Writes all accumulated log entries to an S3 bucket as a text file.
    
    Args:
        text_file_content (list): List of log entries to write
    
    Side Effects:
        - Creates a text file in S3 with all log entries
        - File naming: ec2_start_stop_logs_ASYNC-{timestamp}.txt
        - Stored in: Instance_Auto_Start_STOP_Logs/ prefix
    
    Note:
        The ##bucket placeholder needs to be replaced with actual bucket name
    """
    
    # Merge all log entries into a single string
    text_file_merged_content = ''
    for check in range(len(text_file_content)):
        text_file_merged_content = text_file_merged_content + text_file_content[check] + '\n'

    try:
        timestamp = time.ctime()
        aws_s3_client_bsq = boto3.client('s3')
        aws_s3_client_bsq.put_object(
            Body = str(text_file_merged_content),
            Bucket = 'finalyzer-nonprod-lambda-ec2-start-stop-logs',
            Key = f'Instance_Auto_Start_STOP_Logs/ec2_start_stop_logs_ASYNC-{timestamp}.txt'
        )
        logger.info('COMMITED LOGS TO S3 BUCKET')
    
    except Exception as e:
        logger.error('FAILED TO COMMIT LOGS TO S3 BUCKET')
        logger.error(e)

def lambda_handler(event, context):
    
    """
    Main Lambda handler function - Entry point for AWS Lambda execution.
    
    Args:
        event (dict): AWS Lambda event object (not used in this function)
        context (object): AWS Lambda context object (not used in this function)
    
    Returns:
        dict: Response with statusCode 200
    
    Workflow:
        1. Retrieve instances tagged for auto-stop (running) and auto-start (stopped)
        2. Check current UTC time:
           - If 14:00 UTC (8 PM IST): Stop instances tagged for auto-stop
           - If 02:00 UTC (8 AM IST): Start instances tagged for auto-start
        3. For each instance:
           - Execute start/stop command
           - Wait for state transition to complete
           - Log the result
        4. Write all logs to S3 bucket
        5. Clean up global variables
    
    Time Zones:
        - Lambda uses UTC time
        - 14:00 UTC = 8:00 PM IST (India Standard Time)
        - 02:00 UTC = 8:00 AM IST (India Standard Time)
    """
    
    # Record start time for execution duration tracking
    start_timestamp = time.time()
    
    # Fetch instances based on tags and current state
    ec2_tagged_for_autostop = get_tagged_ec2_instances_by_state('running')
    ec2_tagged_for_autostart = get_tagged_ec2_instances_by_state('stopped')

    # Initialize log file
    text_file_content.append('<--------------------LOGS STARTED------------------->')
    text_append(text_file_content, 'Lambda Execution Started', '[INFO]')
    
    
    # ==================== QUEUE INITIALIZATION ====================
    # These queues work as stacks (LIFO - Last In, First Out)
    # They process instances in reverse order of discovery
    
    # confirm_action_queue: Stores boolean values (True/False) indicating if stop action succeeded
    # Used only in auto-stop logic to track which instances were successfully stopped
    confirm_action_queue = []
    
    # instance_id_queue: Stores EC2 instance IDs that need to be processed
    # Used in both auto-stop and auto-start logic
    instance_id_queue = []


    # Get current UTC time
    timecheck = time.gmtime()

    # Counter for total instances operated on
    operated_instance_count = 0
    
    # ==================== AUTO-STOP LOGIC (8 PM IST / 14:00 UTC) ====================
    if timecheck[3] == 14:
        logger.info('Auto-Stop passed Time check')
        text_append(text_file_content,'Auto-Stop passed Time check', '[INFO]')
        
        
        # ========== PHASE 1: BUILD THE QUEUES ==========
        # Iterate through all running instances tagged for auto-stop
        # and add them to both queues simultaneously
        for reservation in ec2_tagged_for_autostop['Reservations']:
            for instance in reservation['Instances']:
                instance_id = instance['InstanceId']
                
                # Attempt to stop the instance and capture the confirmation status
                confirm_action = stop_single_ec2_instance(instance_id)
                
                # Add confirmation status (True/False) to the action queue
                confirm_action_queue.append(confirm_action)
                
                # Add instance ID to the instance queue
                # Both queues maintain parallel structure: same index = same instance
                instance_id_queue.append(instance_id)

        
        # ========== PHASE 2: PROCESS THE QUEUES ==========
        # Process instances one by one until all are handled
        # Uses stack behavior: processes last-added instance first (LIFO)
        while len(instance_id_queue) != 0:
            
            # Access the LAST element (index -1) in both queues
            # This creates LIFO (stack) behavior instead of FIFO (queue)
            
            # Check if the stop action was denied for this instance
            if confirm_action_queue[-1] == False:
                # Log critical error - instance could not be stopped
                logger.critical('STOP ACTION DENIED for INSTANCE ID :' + instance_id_queue[-1] + ', Name : ' + instance_name_from_id(instance_id_queue[-1]))
                text_append(text_file_content, 'STOP ACTION DENIED for INSTANCE ID :' + instance_id_queue[-1] + ', Name : ' + instance_name_from_id(instance_id_queue[-1]), '[CRITICAL]')
                
                # Remove this instance from both queues (last element)
                confirm_action_queue.pop()
                instance_id_queue.pop()
                
            else:
                # Stop action was confirmed - proceed with monitoring
                logger.info('STOP ACTION CONFIRMED :' + instance_id_queue[-1] + ', Name : ' + instance_name_from_id(instance_id_queue[-1]))
                text_append(text_file_content, 'STOPPING INSTANCE ID :' + instance_id_queue[-1] + ', Name : ' + instance_name_from_id(instance_id_queue[-1]), '[INFO]')
                
                # Find the full instance details from the original response
                for reservation in ec2_tagged_for_autostop['Reservations']:
                    for instance in reservation['Instances']:
                        # Match the instance ID from queue with full instance data
                        if instance['InstanceId'] == instance_id_queue[-1]:
                            # Get initial state after stop command
                            instance_new_state = refresh_instance_state(instance_id_queue[-1],confirm_action_queue[-1])
                            log_refreshed_instance_state(instance, instance_new_state)
                            
                            # ========== POLLING LOOP ==========
                            # Wait for instance to reach 'stopped' state
                            # Polls every second until confirmation
                            while True and confirm_action:
                                time.sleep(1)  # Wait 1 second between checks
                                
                                # Check current state of the instance
                                instance_new_state = refresh_instance_state(instance_id_queue[-1])
                                
                                # If instance has reached stopped state, exit polling loop
                                if instance_new_state == 'stopped':
                                    logger.info('CONFIRMED STOPPED STATE :' + instance_id_queue[-1] + ', Name : ' + instance_name_from_id(instance_id_queue[-1]))
                                    text_append(text_file_content, 'CONFIRMED STOPPED STATE :' + instance_id_queue[-1]+ ', Name : ' + instance_name_from_id(instance_id_queue[-1]), '[INFO]')
                                    operated_instance_count += 1
                                    break  # Exit while loop, move to next instance
                
                # Remove processed instance from both queues
                confirm_action_queue.pop()
                instance_id_queue.pop()
                
        # ========== CLEANUP AFTER AUTO-STOP ==========
        # Clear queues to prevent data persistence across Lambda invocations
        # This is critical because Lambda containers can be reused
        confirm_action_queue.clear()
        instance_id_queue.clear()

    else: 
        # Not the scheduled time for auto-stop
        logger.info('Auto-Stop will Only be triggered at 8 pm IST')
        text_append(text_file_content,'Auto-Stop will Only be triggered at 8 pm IST ', '[INFO]')
    
    
    # ==================== AUTO-START LOGIC (8 AM IST / 02:00 UTC) ====================
    if timecheck[3] == 2:
        logger.info('Auto-Start passed Time check')
        text_append(text_file_content,'Auto-Start passed Time check', '[INFO]')
    
    # ========== PHASE 1: BUILD THE QUEUE ==========
        # Iterate through all stopped instances tagged for auto-start
        # Note: Only uses instance_id_queue, no confirmation queue needed
        for reservation in ec2_tagged_for_autostart['Reservations']:
            for instance in reservation['Instances']:
                instance_id = instance['InstanceId']
                
                # Start the instance immediately (no confirmation check)
                start_single_ec2_instance(instance_id)
                
                # Add instance ID to queue for monitoring
                instance_id_queue.append(instance_id)

    # ========== PHASE 2: PROCESS THE QUEUE ==========
        # Process instances one by one using stack (LIFO) behavior
        while len(instance_id_queue) != 0:
            # Access the LAST element (index -1) from the queue
            logger.info('STARTED INSTANCE ID :' + instance_id_queue[-1]  + ', Name : ' + instance_name_from_id(instance_id_queue[-1]))
            text_append(text_file_content, 'STARTED INSTANCE ID :' + instance_id_queue[-1] + ', Name : ' + instance_name_from_id(instance_id_queue[-1]), '[INFO]')
            
            # Get current state after start command
            instance_new_state = refresh_instance_state(instance_id_queue[-1])
            operated_instance_count += 1
            
            # Find the full instance details from the original response
            for instance in reservation['Instances']:
                # Match the instance ID from queue with full instance data
                if instance['InstanceId'] == instance_id_queue[-1]:
                    instance_new_state = refresh_instance_state(instance_id_queue[-1])
                    log_refreshed_instance_state(instance, instance_new_state)
                    
                    # ========== POLLING LOOP ==========
                    # Wait for instance to reach 'running' state
                    # Polls every second until confirmation
                    while True:
                        time.sleep(1)  # Wait 1 second between checks
                        
                        # Check current state of the instance
                        instance_new_state = refresh_instance_state(instance_id_queue[-1])
                        
                        # If instance has reached running state, exit polling loop
                        if instance_new_state == 'running':
                            logger.info('CONFIRMED STARTED STATE :' + instance_id_queue[-1] + ', Name : ' + instance_name_from_id(instance_id_queue[-1]))
                            text_append(text_file_content, 'CONFIRMED STARTED STATE :' + instance_id_queue[-1] + ', Name : ' + instance_name_from_id(instance_id_queue[-1]), '[INFO]')
                            break  # Exit while loop, move to next instance
            
            # Remove processed instance from queue
            instance_id_queue.pop()

    else:
        # Not the scheduled time for auto-start
        logger.info('Auto-Start will Only be triggered at 8 am IST')
        text_append(text_file_content,'Auto-Start will Only be triggered at 8 am IST', '[INFO]')

    # ==================== CLEANUP AND LOGGING ====================
    # Add execution summary to logs
    text_append(text_file_content, 'Lambda Execution Completed', '[INFO]')
    text_append(text_file_content, 'Total Instances Operated : ' + str(operated_instance_count), '[INFO]')
    
    # Calculate and log execution time
    stop_timestamp = time.time()
    text_file_content.append('Lambda Execution Time : ' + str(stop_timestamp - start_timestamp) + ' seconds')
    text_file_content.append('<--------------------LOGS ENDED------------------->')
    
    # Commit all logs to S3
    text_file_commit(text_file_content)
    
    # Clear global variables to prevent data persistence across Lambda invocations
    text_file_content.clear() # Clearing any persisted data before another lambda run
    instance_id_queue.clear() # Clearing any persisted data before another lambda run
    
    # Return success response
    return {
        'statusCode': 200
    }