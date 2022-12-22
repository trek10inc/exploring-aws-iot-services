import paho.mqtt.client as mqtt 
from random import randint
import ssl
import traceback

#---------------------------------------------------------------
# important settings
topic = "trek10/initial"
client_id_prefix = "aws-trek10-thing-"
broker = "a52tv5ff7ph83-ats.iot.us-west-1.amazonaws.com"
port = 8883

# certificate params
certificate = "/path/to/aws-certs/trek10-cert.pem"
private_key = "/path/to/aws-certs/trek10-priv-key.pem"
ca_bundle = "/path/to/aws-certs/AmazonRootCA1.pem"
#---------------------------------------------------------------

# other misc settings
device_id = randint(0, 3)
client_id = client_id_prefix + str(device_id)
keepalive = 60

paho_erro_codes = {0: "Connection successful",
    1: "Connection refused – incorrect protocol version",
    2: "Connection refused – invalid client identifier",
    3: "Connection refused – server unavailable",
    4: "Connection refused – bad username or password",
    5: "Connection refused – not authorised",
    100: "Connection refused - other things"
}

def on_connect(client, userdata, flags, rc):
    print("Connected with result code " + str(rc))
    if rc == 0:
        # Subscribing in on_connect() means that if we lose the connection
        # and reconnect then subscriptions will be renewed.
        client.subscribe(topic, qos=0)
    else:
        print("Problem connecting: " + str(paho_erro_codes[rc]))
        client.disconnect()

def on_log(client, userdata, level, buf):
  print("log: ", buf)

def on_message(client, userdata, message):
    print("Topic: " + message.topic)
    print("Received message: " + message.payload.decode("utf-8"))

if __name__ == '__main__':
    try:
        client = mqtt.Client(client_id)
        client.tls_set(ca_certs=ca_bundle,
            certfile=certificate,
            keyfile=private_key,
            cert_reqs=ssl.CERT_REQUIRED,
            tls_version=ssl.PROTOCOL_TLSv1_2,
            ciphers=None)

        # to help with troubleshooting
        # client.on_log = on_log

        client.on_connect = on_connect

        client.on_message = on_message

        # connect and publish
        client.connect(broker, port, keepalive=keepalive)
        client.loop_forever()

    except Exception as e:
        traceback.print_exc()
