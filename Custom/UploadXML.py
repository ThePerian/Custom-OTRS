#!/usr/bin/env python
# -*- coding: utf-8 -*-
import urllib2
import re
import xml.etree.ElementTree as ET
import sys
import os
import json
from subprocess import call

configPath = os.path.dirname(__file__)
if not configPath.endswith("/") and configPath <> "":
    configPath += "/"
config = json.load(open(configPath + "config.json"))
for item in config:
    config[item] = config[item].decode().encode('utf8')

if ('--fix' in sys.argv) or ('-f' in sys.argv):
    fix = True
    f = open(config["error_clients"])
    clientsToFix = [line.rstrip('\n') for line in f]
    f.close()
else:
    fix = False

systemCode = json.load(open(config["system_code"]))

urlClient = config["url_client"]
urlUser = config["url_user"]
errorsFile = open(config["errors"], 'w+')
errorClientsFile = open(config["error_clients"], 'w+')
tree = ET.parse(config["1clk"])
root = tree.getroot()
processed = 0
clients = root.findall("./Объект/[@Тип='СправочникСсылка.Clients']".decode('utf8'))

for client in clients:
    if (fix and (client.get('Нпп'.decode('utf8')) not in clientsToFix)):
        continue
    
    processed += 1
    clientData = {'to' : 'id', 'name' : 'name', 'fullName' : 'title', 'inn' : 'inn', 'comment' : 'verbose_title', 'active' : 'active'}
    err = False
    for var in clientData.keys():
        try:
            clientData[var] = client.find(("./Свойство/[@Имя='%s']/Значение" % clientData[var]).decode('utf8')).text.strip()
        except (RuntimeError, AttributeError) as err:
            clientData[var] = ''
            errorString = "Error getting parameter %s in client no.%s: %s" % (var, client.get('Нпп'.decode('utf8')), format(err))
            print >>errorsFile, errorString.encode('utf8')
            print >>errorClientsFile, client.get('Нпп'.decode('utf8'))
            print "Error getting parameter %s in client no.%s: %s" % (var, client.get('Нпп'.decode('utf8')), format(err))
            continue
    if clientData['to'] == '' or clientData['name'] == '':
        continue
    if clientData['active'] == 'true':
        clientData['active'] = 1
    else:
        clientData['active'] = 0

    systems = ""
    for system in client.findall("./ТабличнаяЧасть/[@Имя='systems']/Запись".decode('utf8')):
        try:
            distr = system.find("./Свойство/[@Имя='distr']/Значение".decode('utf8')).text.strip()
            abbr = system.find("./Свойство/[@Имя='abbr']/Значение".decode('utf8')).text.strip().upper()
        except (RuntimeError, AttributeError) as err:
            errorString = "Error getting system data in client no.%s: %s" % (client.get('Нпп'.decode('utf8')), format(err))
            print >>errorsFile, errorString.encode('utf8')
            print >>errorClientsFile, client.get('Нпп'.decode('utf8'))
            print errorString
            continue
        system = "%s_%s" % (systemCode[abbr], distr.zfill(6))
        if (abbr not in systems):
            systems += "\"" + abbr + "\","
        result = call(["redis-cli", "set", system, clientData['to']], stdout=open(os.devnull, 'wb'))
        if (result != 0):
            print "Setting %s = %s: %s" % (system, clientData['to'], result)

    dataClient = "{\"CustomerCompany\":{\"CustomerCompanyName\":\"%s\",\"CustomerID\":\"%s\",\"CustomerCompanyID\":\"%s\",\"ValidID\":\"%s\",\"Comment\":\"%s\",\"DynamicFields\":{\"CustomerCompanyFullName\":\"%s\",\"CustomerCompanyINN\":\"%s\",\"MaintainedBases\":[%s]}}}" % (clientData['name'].replace('"','\\"'), clientData['to'], clientData['to'], clientData['active'], clientData['comment'].replace('"','\\"'), clientData['fullName'].replace('"','\\"'), clientData['inn'], systems.strip(','))
    reqClient = urllib2.Request(urlClient)
    reqClient.add_header('Content-Type', 'application/json')
    try:
        response = urllib2.urlopen(reqClient, dataClient.encode('utf8'))
    except (RuntimeError, urllib2.HTTPError) as err:
        errorString = "Error while processing request for client %s: %s" % (clientData['name'], format(err))
        print >>errorsFile, errorString.encode('utf8')
        print >>errorClientsFile, client.get('Нпп'.decode('utf8'))
        print "Error while processing request for client %s: %s" % (clientData['name'], format(err))
        continue
    else:
        print "%s %s: %s" % (clientData['to'], clientData['name'], response.getcode())  

    usercount = 1
    for user in client.findall("./ТабличнаяЧасть/[@Имя='Client_Employees']/Запись".decode('utf8')):
        try:
            userFullName = user.find("./Свойство/[@Имя='name']/Значение".decode('utf8')).text.strip().replace('\t',' ')
        except (RuntimeError, AttributeError) as err:
            errorString = "Error getting parameter userFullName in client user %s %s: %s" % (clientData['to'], userFullName, format(err))
            print >>errorsFile, errorString.encode('utf8')
            print >>errorClientsFile, client.get('Нпп'.decode('utf8'))
            print "Error getting parameter userFullName in client user %s %s: %s" % (clientData['to'], userFullName, format(err))
            continue
        if (' ' in userFullName):
            userFirstName = userFullName[userFullName.index(' '):]
            userLastName = userFullName[:userFullName.index(' ')]
        else:
            userFirstName = '.';
            userLastName = userFullName;
        try:
            hasEmail = user.find("./Свойство/[@Имя='email']/Значение".decode('utf8'))
            if ((hasEmail is not None) and (re.match("[^@]+@[^@]+\.[^@]+$", hasEmail.text))):
                userEmail = hasEmail.text.strip()
            else:
                userEmail = "client%d-%s@noemail.ru" % (usercount, clientData['to'])
        except (RuntimeError, AttributeError) as err:
            errorString = "Error getting parameter email in client user %s %s: %s" % (clientData['to'], userFullName, format(err))
            print >>errorsFile, errorString.encode('utf8')
            print >>errorClientsFile, client.get('Нпп'.decode('utf8'))
            print "Error getting parameter email in client user %s %s: %s" % (clientData['to'], userFullName, format(err))
            continue
        usercount += 1
        
        dataUser = "{\"CustomerUser\":{\"UserCustomerID\":\"%s\",\"UserLogin\":\"%s\",\"ID\":\"%s\",\"UserFirstname\":\"%s\",\"UserLastname\":\"%s\",\"UserEmail\":\"%s\",\"ValidID\":\"1\"}}" % (clientData['to'], userFullName, userFullName, userFirstName, userLastName, userEmail)
        reqUser = urllib2.Request(urlUser)
        reqUser.add_header('Content-Type', 'application/json')
        
        try:
            response = urllib2.urlopen(reqUser, dataUser.encode('utf8'))
        except (RuntimeError, urllib2.HTTPError) as err:
            errorString = "Error while processing request for client user %s %s: %s" % (clientData['to'], userFullName, format(err))
            print >>errorsFile, errorString.encode('utf8')
            print >>errorClientsFile, client.get('Нпп'.decode('utf8'))
            print "Error while processing request for client user %s %s: %s" % (clientData['to'], userFullName, format(err))
            continue
        else:
            if (response.getcode() != 200):
                print "%s %s: %s" % (clientData['to'], userFullName, response.getcode())
    print "Created users for client %s" % clientData['to']
    if (fix):
        percent = round(float(processed*100)/len(clientsToFix), 2)
    else:
        percent = round(float(processed*100)/len(clients), 2)
    print "Processed %s%%" % percent

errorsFile.close()
errorClientsFile.close()
