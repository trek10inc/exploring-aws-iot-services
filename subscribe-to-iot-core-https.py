import paho.mqtt.client as mqtt 
from random import randint
import ssl
import traceback
import os
import json
import time

#---------------------------------------------------------------
# important settings
config_file = 'conf/config.json'
client_id_prefix = "aws-trek10-thing-"
IoT_protocol_name = "x-amzn-mqtt-ca"
#---------------------------------------------------------------

# other misc settings
device_id = randint(0, 3)
client_id = client_id_prefix + str(device_id)

paho_erro_codes = {0: "Connection successful",
    1: "Connection refused - incorrect protocol version",
    2: "Connection refused - invalid client identifier",
    3: "Connection refused - server unavailable",
    4: "Connection refused - bad username or password",
    5: "Connection refused - not authorised",
    100: "Connection refused - other things"
}

def on_connect(client, userdata, flags, rc):
    print("Connected with result code " + str(rc))
    if rc == 0:
        # Subscribing in on_connect() means that if we lose the connection
        # and reconnect then subscriptions will be renewed.
        client.subscribe(config['topic'], qos = 1)
    else:
        print("Problem connecting: " + str(paho_erro_codes[rc]))
        client.disconnect()

def on_log(client, userdata, level, buf):
  print("log: ", buf)

def on_message(client, userdata, message):
    print("Topic: " + message.topic)
    print("Received message: " + message.payload.decode("utf-8"))

def ssl_alpn():
    try:
        ssl_context = ssl.create_default_context()
        ssl_context.set_alpn_protocols([IoT_protocol_name])
        ssl_context.load_verify_locations(cafile = config['ca_bundle'])
        ssl_context.load_cert_chain(certfile = config['certificate'], keyfile = config['private_key'])
        return ssl_context

    except Exception as e:
        traceback.print_exc()

if __name__ == '__main__':
    try:
        # look for config dir
        if not os.path.exists('conf'):
            os.makedirs('conf')

        # look for config file
        if not os.path.exists(config_file):
            config = { "topic": "trek10/initial", "broker": "", "port": 8883, "keepalive": 60, "certificate": "", "private_key": "", "ca_bundle": "" }
            
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
        ssl_context = ssl_alpn()
        client.tls_set_context(context = ssl_context)

        # client.tls_set(ca_certs = config['ca_bundle'],
        #     certfile = config['certificate'],
        #     keyfile = config['private_key'],
        #     cert_reqs = ssl.CERT_REQUIRED,
        #     tls_version = ssl.PROTOCOL_TLSv1_2,
        #     ciphers = None)

        # to help with troubleshooting
        # client.on_log = on_log

        client.on_connect = on_connect

        client.on_message = on_message

        # connect and loop
        client.connect(config['broker'], 443, keepalive = config['keepalive'])
        client.loop_forever()

    except Exception as e:
        traceback.print_exc()
