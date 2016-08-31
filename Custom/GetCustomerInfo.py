#!/usr/bin/env python
import time
import httplib
import sys
import xml.etree.ElementTree as ET
import os
import json

configPath = os.path.dirname(__file__)
if not configPath.endswith("/") and configPath <> "":
    configPath += "/"
config = json.load(open(configPath + "config.json"))

for item in config:
    config[item] = config[item].decode().encode('utf8')

def callback(CodeTO):
    server_addr = config["server_addr_main"]
    service_action = config["service_action_main"]

    body = """
        <soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope" xmlns:igbx="igbx">
        <soap:Header/>
        <soap:Body>
        <igbx:GetCard>
        <igbx:CodeTO>""" + CodeTO + """</igbx:CodeTO>
        </igbx:GetCard>
        </soap:Body>
        </soap:Envelope>"""

    request = httplib.HTTPConnection(server_addr)
    request.putrequest("POST", service_action)
    request.putheader("Accept", "application/pdf, application/soap+xml, application/dime, multipart/related, text/*")
    request.putheader("Content-Type", "application/soap+xml;charset=utf-8;action='igbx#WSInvoice:GetCard'")
    request.putheader("SOAPAction", 'http://' + server_addr + service_action)
    request.putheader("Content-Length", str(len(body)))
    request.putheader("Authorization", config["authorization_main"])
    request.endheaders()
    request.send(body)
    response = request.getresponse().read()

    return response

CodeTO = sys.argv[1]
response = callback(CodeTO)

namespaces = {'soap': 'http://www.w3.org/2003/05/soap-envelope', 'm': 'igbx'}
tree = ET.fromstring(response)
encodedString = tree.find('./soap:Body/m:GetCardResponse/m:return', namespaces).text

print encodedString
