import paho.mqtt.client as mqtt 
from random import randint
import ssl
import traceback
import os
import json
import time
import requests
import threading
import sys
import trace

#---------------------------------------------------------------
# important settings
config_file_prefix = 'conf/config-'
device_id = 1
thing_name = 'trek10-thing-' + str(device_id)
client_id = thing_name
config_file = config_file_prefix + str(device_id) + '.json'

# important topics
notify_topic        = '$aws/things/' + thing_name + '/jobs/notify'
notify_next_topic   = '$aws/things/' + thing_name + '/jobs/notify-next'
pending_jobs_topic  = '$aws/things/' + thing_name + '/jobs/get'
accepted_jobs_topic = '$aws/things/' + thing_name + '/jobs/get/accepted'
rejected_jobs_topic = '$aws/things/' + thing_name + '/jobs/get/rejected'
#---------------------------------------------------------------

print("Working with client id: " + client_id)

# dictionary to hold current job info
# maybe write this to a file, instead?
current_job = {}

# paho error codes
paho_erro_codes = {0: "Connection successful",
    1: "Connection refused – incorrect protocol version",
    2: "Connection refused – invalid client identifier",
    3: "Connection refused – server unavailable",
    4: "Connection refused – bad username or password",
    5: "Connection refused – not authorised",
    100: "Connection refused - other things"
}

# Custom thread so we can cancel a job and back out the changes
class JobThread(threading.Thread):
    # constructor
    def __init__(self, *args, **keywords):
        threading.Thread.__init__(self, *args, **keywords)
        self.killed = False

    def start(self):
        self.__run_backup = self.run
        self.run = self.__run
        threading.Thread.start(self)

    def __run(self):
        sys.settrace(self.globaltrace)
        self.__run_backup()
        self.run = self.__run_backup

    def globaltrace(self, frame, event, arg):
        if event == 'call':
            return self.localtrace
        else:
            return None

    def localtrace(self, frame, event, arg):
        if self.killed:
            if event == 'line':
                raise SystemExit()
        return self.localtrace

    def kill(self):
        # we want to work with our global dictionary
        global current_job

        # what action did we take?
        if current_job['action'] == 'config':
            # replace current config
            if 'backup_config_file' in current_job \
                    and os.path.exists(current_job['backup_config_file']):
                    
                # delete current config file
                os.unlink(config_file)

                with open(current_job['backup_config_file'], "r") as read_handle:
                    config = json.load(read_handle)

                with open(config_file, "w") as write_handle:
                    json.dump(config, write_handle)

        # reset the current job dictionary
        current_job = {}
        
        # mark killed as true
        self.killed = True

def on_connect(client, userdata, flags, rc):
    print("---------------------------------------------------------------------")
    print("In on_connect with result code " + str(rc))
    if rc == 0:
        # Subscribing in on_connect() means that if we lose the connection
        # and reconnect then subscriptions will be renewed.
        client.subscribe(notify_topic, qos = 1)

        # grab the pending jobs
        publish(client, pending_jobs_topic, json.dumps({ "clientToken": client_id }))
    else:
        print("Problem connecting: " + str(paho_erro_codes[rc]))
        client.disconnect()

def on_log(client, userdata, level, buf):
    print("---------------------------------------------------------------------")
    print("Log output: ", buf)

def publish(client, topic, message):
    result = client.publish(topic, message, qos = 1)
    # result: [0, 1]

    status = result[0]
    # print("status = " + {status})

    if status == 0:
        print("---------------------------------------------------------------------")
        print("Published to " + topic + ": " + message)
    else:
        print("---------------------------------------------------------------------")
        print("Failed to send message to topic " + config['topic'])

def on_message(client, userdata, message):
    print("---------------------------------------------------------------------")
    print("Topic: " + message.topic)
    print("Received message: " + message.payload.decode("utf-8"))

    # we want to work with our global dictionary
    global current_job
    
    # pull the payload into a dictionary
    payload = json.loads(message.payload.decode('utf-8'))

    if message.topic == accepted_jobs_topic:
        if 'inProgressJobs' in payload:
            in_progress_jobs = payload['inProgressJobs']

        if 'queuedJobs' in payload:
            queued_jobs = payload['queuedJobs']

        if len(queued_jobs) > 0 and len(in_progress_jobs) == 0:
                # save the current job for later
                current_job = payload['queuedJobs'][0]

                # add some data to current_job
                current_job['get_topic']                = '$aws/things/' + thing_name + '/jobs/' + current_job['jobId'] + '/get'
                current_job['get_accepted_topic']       = '$aws/things/' + thing_name + '/jobs/' + current_job['jobId'] + '/get/accepted'
                current_job['get_rejected_topic']       = '$aws/things/' + thing_name + '/jobs/' + current_job['jobId'] + '/get/rejected'
                current_job['update_topic']             = '$aws/things/' + thing_name + '/jobs/' + current_job['jobId'] + '/update'
                current_job['update_accepted_topic']    = '$aws/things/' + thing_name + '/jobs/' + current_job['jobId'] + '/update/accepted'
                current_job['update_rejected_topic']    = '$aws/things/' + thing_name + '/jobs/' + current_job['jobId'] + '/update/rejected'

                # Subscribing is unnecessary. These topics will automatically be subscribed to 
                # client.subscribe(current_job['get_accepted_topic'], qos = 1)
                # client.subscribe(current_job['get_rejected_topic'], qos = 1)
                # client.subscribe(current_job['update_accepted_topic'], qos = 1)
                # client.subscribe(current_job['update_rejected_topic'], qos = 1)

                # publish to get topic and hope for successful reply
                publish(client, current_job['get_topic'], json.dumps(
                        {
                            "includeJobDocument": "true",
                            "clientToken": client_id
                        }
                    )
                )

    if message.topic == notify_topic:
        if 'jobs' in payload:
            jobs = payload['jobs']

            # we are not working a job and there is a new job to execute
            if 'QUEUED' in jobs \
                    and 'IN_PROGRESS' not in jobs \
                    and not current_job:

                # save the current job for later
                current_job = payload['jobs']['QUEUED'][0]

                # add some data to current_job
                current_job['get_topic']                = '$aws/things/' + thing_name + '/jobs/' + current_job['jobId'] + '/get'
                current_job['get_accepted_topic']       = '$aws/things/' + thing_name + '/jobs/' + current_job['jobId'] + '/get/accepted'
                current_job['get_rejected_topic']       = '$aws/things/' + thing_name + '/jobs/' + current_job['jobId'] + '/get/rejected'
                current_job['update_topic']             = '$aws/things/' + thing_name + '/jobs/' + current_job['jobId'] + '/update'
                current_job['update_accepted_topic']    = '$aws/things/' + thing_name + '/jobs/' + current_job['jobId'] + '/update/accepted'
                current_job['update_rejected_topic']    = '$aws/things/' + thing_name + '/jobs/' + current_job['jobId'] + '/update/rejected'
                
                # Subscribing is unnecessary. These topics will automatically be subscribed to 
                # client.subscribe(current_job['get_accepted_topic'], qos = 1)
                # client.subscribe(current_job['get_rejected_topic'], qos = 1)
                # client.subscribe(current_job['update_accepted_topic'], qos = 1)
                # client.subscribe(current_job['update_rejected_topic'], qos = 1)

                # publish to get topic and hope for successful reply
                publish(client, current_job['get_topic'], json.dumps(
                        {
                            "includeJobDocument": "true",
                            "clientToken": client_id
                        }
                    )
                )

    # we are already working a job
    if current_job:
        # our job was accepted
        if message.topic == current_job['get_accepted_topic']:
            if 'execution' in payload \
                    and 'jobDocument' in payload['execution'] \
                    and payload['execution']['status'] == 'QUEUED':

                # call our threaded function
                config_thread = JobThread(target = job_handler, name = client_id, args = (client, payload))
                
                # start the thread
                config_thread.start()
        
        elif message.topic == current_job['get_rejected_topic']:
            print("Error: Message published to get rejected topic")
            if "code" in payload \
                    and payload['code'] == "TerminalStateReached":
                
                if current_job['action'] == 'config':
                    print("Error: Killing job and reverting changes to config.")

                current_job['current_thread'].kill()

                # reset the current job dictionary
                current_job = {}


        elif message.topic == current_job['update_rejected_topic']:
            print("Error: The attempt to update rejected topic.")

def start_process(target, name, args):
        process = Process(target=target, name=name, args=args, daemon=True)
        process.start()

def job_handler(client, payload):
    # we want to work with our global dictionary
    global current_job

    # save current thread 
    current_job['current_thread'] = threading.current_thread()

    # mark job as IN_PROGRESS
    # print("---------------------- Setting job IN_PROGRESS ----------------------")
    publish(client, current_job['update_topic'], json.dumps({ "status" : "IN_PROGRESS" }))

    # what is the action?
    action = payload['execution']['jobDocument']['action']

    # remember the action for later
    current_job['action'] = action

    # sleep for a bit in case cancelled or deleted
    time.sleep(15)

    # check if job has been cancelled or deleted
    # print("------------------------ Checking job status ------------------------")
    publish(client, current_job['get_topic'], json.dumps(
            {
                "includeJobDocument": "false",
                "clientToken": client_id
            }
        )
    )

    # sleep for a bit in case cancelled or deleted
    time.sleep(10)

    if action == 'config':
        # what is the url of our config file store in S3?
        url = payload['execution']['jobDocument']['url']

        try:
            # sending get request and saving the response as response object
            response = requests.get(url)

            # extracting data in json format
            config = response.json()

            # print("---------------------- Setting job IN_PROGRESS ----------------------")
            print("Doing work. Fetching job file and updating config.")

            # backup current config
            if os.path.exists(config_file):
                with open(config_file, "r") as read_handle:
                    current_config = json.load(read_handle)

                epoch = int(time.time())

                backup_config_file = config_file + '.' + str(epoch)

                # save this in case of job cancellation
                current_job['backup_config_file'] = backup_config_file
                # current_job['config_file'] = config_file

                with open(backup_config_file, "w") as write_handle:
                    json.dump(current_config, write_handle)

            # write data to file
            with open(config_file, "w") as write_handle:
                json.dump(config, write_handle)

        except Exception as e:
            # mark job as FAILED
            publish(client, current_job['update_topic'], json.dumps({ "status" : "FAILED" }))

            # reset the current job dictionary
            current_job = {}

            # print traceback
            traceback.print_exc()

        # sleep for a bit in case cancelled or deleted
        time.sleep(10)

        # check if job has been cancelled or deleted
        # print("------------------------ Checking job status ------------------------")
        publish(client, current_job['get_topic'], json.dumps(
                {
                    "includeJobDocument": "false",
                    "clientToken": client_id
                }
            )
        )

        # sleep for a bit in case cancelled or deleted
        time.sleep(10)

        # mark job status as SUCCEEDED
        publish(client, current_job['update_topic'], json.dumps({ "status" : "SUCCEEDED" }))

        # reset the current job dictionary
        current_job = {}


# create our job thread
# job_thread = JobThread()

if __name__ == '__main__':
    try:
        # look for config dir
        if not os.path.exists('conf'):
            os.makedirs('conf')

        # look for config file
        if not os.path.exists(config_file):
            config = { "topic": "trek10/initial", "broker": "", "port": 8883, "keepalive": 60, "certificate": "", "private_key": "", "ca_bundle": "", "scale": "" }
            
            # write out a default config file
            with open(config_file, "w") as write_handle:
                json.dump(config, write_handle)
                print("Error: No config file was found. Please populate " + config_file + " with valid values.")
                quit()
        else:
            # grab our config data
            with open(config_file, "r") as read_handle:
                config = json.load(read_handle)
        
        client = mqtt.Client(client_id)

        client.tls_set(ca_certs = config['ca_bundle'],
            certfile = config['certificate'],
            keyfile = config['private_key'],
            cert_reqs = ssl.CERT_REQUIRED,
            tls_version = ssl.PROTOCOL_TLSv1_2,
            ciphers = None)

        # to help with troubleshooting
        # client.on_log = on_log

        # what do we do on connection attempt?
        client.on_connect = on_connect

        # what do we do when we receive a message?
        client.on_message = on_message

        # connect and loop
        client.connect(config['broker'], config['port'], keepalive = config['keepalive'])
        client.loop_forever()

    except Exception as e:
        # print traceback
        traceback.print_exc()