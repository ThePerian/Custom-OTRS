#!/usr/bin/env python
import pika
import time
import httplib
import os
import json

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
    server_addr = config["server_addr_hotline"]
    service_action = config["service_action_hotline"]

    body = """
        <soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope" xmlns:ctod="http://localhost/1CTOdev">
        <soap:Header/>
        <soap:Body>
        <ctod:TicketCreate>
        <ctod:TicketJSON>
        """ + body + """
        </ctod:TicketJSON>
        </ctod:TicketCreate>
        </soap:Body>
        </soap:Envelope>"""

    request = httplib.HTTPConnection(server_addr)
    request.putrequest("POST", service_action)
    request.putheader("Accept", "application/soap+xml, application/dime, multipart/related, text/*")
    request.putheader("Content-Type", "text/xml; charset=utf-8")
    request.putheader("SOAPAction", 'http://' + server_addr + service_action)
    request.putheader("Content-Length", str(len(body)))
    request.putheader("Authorization", config["authorization_main"])
    request.endheaders()
    request.send(body)
    response = request.getresponse().read()

    print(" [x] Got response: %r" % response) #time.sleep(body.count(b'.'))
    print(" [x] Done")
    ch.basic_ack(delivery_tag = method.delivery_tag)

channel.basic_qos(prefetch_count=1)
channel.basic_consume(callback,
                      queue='task_queue')

channel.start_consuming()
