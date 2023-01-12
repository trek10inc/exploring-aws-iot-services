import paho.mqtt.client as mqtt 
from random import randint, uniform
import ssl
import time
import os
import json
import traceback

#---------------------------------------------------------------
# important settings
topic = "trek10/initial"
client_id_prefix = "aws-trek10-thing-"
broker = "d62tv5ad7ph83-ats.iot.us-west-1.amazonaws.com" 
port = 443
keepalive = 60
IoT_protocol_name = "x-amzn-mqtt-ca"

# certificate params
certificate = "/data/dev/iot/aws-certs/trek10-cert.pem"
private_key = "/data/dev/iot/aws-certs/trek10-priv-key.pem"
ca_bundle = "/data/dev/iot/aws-certs/AmazonRootCA1.pem"
#---------------------------------------------------------------

# other misc settings
device_id = randint(0, 3)
client_id = client_id_prefix + str(device_id)

# set min and max for each metric
temp_min_c = -26
temp_max_c = 55

temp_min_f = -15
temp_max_f = 130

humidity_min = 0
humidity_max = 100

velocity_min = 0
velocity_max = 160

bearing_min = 0
bearing_max = 359

barometer_min = 25.9
barometer_max = 32.01

# what is maximum data point percent change?
max_change = 3

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

    if rc != 0:
        print("Problem connecting: " + str(paho_erro_codes[rc]))
        client.disconnect()

def on_log(client, userdata, level, buf):
  print("log: ", buf)

def publish(client):
    result = client.publish(topic, message, qos = 1)
    # result: [0, 1]

    status = result[0]
    # print("status = " + {status})

    if status == 0:
        print("Published message: " + message)
    else:
        print("Failed to send message to topic " + topic)

def ssl_alpn():
    try:
        ssl_context = ssl.create_default_context()
        ssl_context.set_alpn_protocols([IoT_protocol_name])
        ssl_context.load_verify_locations(cafile = ca_bundle)
        ssl_context.load_cert_chain(certfile = certificate, keyfile = private_key)
        return ssl_context

    except Exception as e:
        traceback.print_exc()

if __name__ == '__main__':
    try:
        # create a temporary directory if it does exist
        if not os.path.exists('tmp'):
            os.makedirs('tmp')

        # To make it such that data points don't go from one
        # extreme to the other, we'll grab the last set of
        # data points from a file and pick a value slightly
        # above or below (capped at max_change percent). 
        state_file = 'tmp/' + str(device_id) + '.json'

        if os.path.exists(state_file):
            # grab our previous data
            with open(state_file, "r") as read_handle:
                data = json.load(read_handle)

            scale = data['scale']
            temperature = data['temperature']
            humidity = data['humidity']
            barometer = data['barometer']
            wind_velocity = data['wind']['velocity']
            wind_bearing = data['wind']['bearing']

            # temperature
            percent_change = uniform(0, max_change) / 100

            if randint(0, 1) > 0:
                temperature = temperature + (temperature * percent_change)
            else:
                temperature = temperature - (temperature * percent_change)

            if scale == 'c':
                if temperature > temp_max_c:
                    temperature = temp_max_c

                if temperature < temp_min_c:
                    temperature = temp_min_c

            if scale == 'f':
                if temperature > temp_max_f:
                    temperature = temp_max_f

                if temperature < temp_min_f:
                    temperature = temp_min_f

            # humidity
            percent_change = uniform(0, max_change) / 100

            if randint(0, 1) > 0:
                humidity = humidity + (humidity * percent_change)
            else:
                humidity = humidity - (humidity * percent_change)

            if humidity > humidity_max:
                humidity = humidity_max

            if humidity < humidity_min:
                humidity = humidity_min

            # barometer
            percent_change = uniform(0, max_change) / 100

            if randint(0, 1) > 0:
                barometer = barometer + (barometer * percent_change)
            else:
                barometer = barometer - (barometer * percent_change)

            if barometer > barometer_max:
                barometer = barometer_max

            if barometer < barometer_min:
                barometer = barometer_min

            # wind velocity
            percent_change = uniform(0, max_change) / 100

            if randint(0, 1) > 0:
                wind_velocity = wind_velocity + (wind_velocity * percent_change)
            else:
                wind_velocity = wind_velocity - (wind_velocity * percent_change)

            if wind_velocity > velocity_max:
                wind_velocity = velocity_max

            if wind_velocity < velocity_min:
                wind_velocity = velocity_min

            # wind bearing
            percent_change = uniform(0, max_change) / 100

            if randint(0, 1) > 0:
                wind_bearing = wind_bearing + (wind_bearing * percent_change)
            else:
                wind_bearing = wind_bearing - (wind_bearing * percent_change)

            if wind_bearing > bearing_max:
                wind_bearing = bearing_max

            if wind_bearing < bearing_min:
                wind_bearing = bearing_min

        else:
            if randint(0, 1) > 0:
                scale = "c"
                temperature = uniform(temp_min_c, temp_max_c) # celsius
            else:
                scale = "f"
                temperature = uniform(temp_max_f, temp_max_f) # fahrenheit
            
            humidity = uniform(humidity_min, humidity_max)
            barometer = uniform(barometer_min, barometer_max)
            wind_velocity = uniform(velocity_min, velocity_max)
            wind_bearing = randint(bearing_min, bearing_max)

        timestamp = int(time.time()) # epoch

        data = { "scale": scale, "temperature": round(temperature, 2), "humidity": round(humidity, 2), "timestamp": timestamp, "barometer": round(barometer, 2), "wind": { "velocity": round(wind_velocity, 2), "bearing": round(wind_bearing, 2) }, "device": device_id }

        with open(state_file, "w") as write_handle:
            json.dump(data, write_handle)

        # create a string from our json object
        message = json.dumps(data)

        # message = '{"scale": "' + scale + '", "temperature":' + str(temperature) + ', "humidity":' + str(humidity) + ', "timestamp":' + str(timestamp) + ', "barometer":' + str(barometer) + ', "wind": { "velocity":' + str(wind_velocity) + ', "bearing":' + str(wind_bearing) + ' }, "device": ' + str(device_id) + '}'

        # print(f"msg = {message}")

        client = mqtt.Client(client_id)
        ssl_context = ssl_alpn()
        client.tls_set_context(context = ssl_context)

        # client.tls_set(ca_certs = ca_bundle,
        #     certfile = certificate,
        #     keyfile = private_key,
        #     cert_reqs = ssl.CERT_REQUIRED,
        #     tls_version = ssl.PROTOCOL_TLSv1_2, ciphers=None)

        # to help with troubleshooting
        # client.on_log = on_log

        client.on_connect = on_connect

        # connect and loop
        client.connect(broker, port, keepalive=keepalive)
        client.loop_start()
        publish(client)

        # need to let publish finish
        time.sleep(1)

        client.disconnect()

    except Exception as e:
        traceback.print_exc()
