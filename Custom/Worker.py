#!/usr/bin/env python
import pika
import httplib
import os
import json
from suds.client import Client
import sys

#z0mg haxx!
#sadly the only way to make suds send cyrillic
reload(sys)
sys.setdefaultencoding('utf-8')

configPath = os.path.dirname(__file__)
if not configPath.endswith("/") and configPath <> "":
    configPath += "/"
config = json.load(open(configPath + "config.json"))
for item in config:
    config[item] = config[item].decode().encode('utf8')

connection = pika.BlockingConnection(pika.ConnectionParameters(
        host='localhost'))
channel = connection.channel()

channel.queue_declare(queue='task_queue', durable=True)
print(' [*] Waiting for messages. To exit press CTRL+C')

def callback(ch, method, properties, body):
    print(" [x] Received %r\n [x] Sending request" % body)
    client = Client(config["wsdl_hotline"], username=config["login_hotline"], password=config["password_hotline"])
    response = client.service.TicketCreate(TicketJSON=body)

    print(" [x] Got response: %r" % response)
    print(" [x] Done")
    ch.basic_ack(delivery_tag = method.delivery_tag)

channel.basic_qos(prefetch_count=1)
channel.basic_consume(callback,
                      queue='task_queue')

channel.start_consuming()
