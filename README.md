Что такое OTRS?
=============
OTRS это Open source Ticket Request System со множеством возможностей для управления
обращениями клиентов по телефону и e-mail. OTRS распространяется по лицензии GNU
AFFERO General Public License (AGPL) и протестирована на Linux, Solaris, AIX,
FreeBSD, OpenBSD и Mac OS 10.x.

Полный список возможностей можно найти в 
[онлайн руководстве](http://otrs.github.io/doc/manual/admin/6.0/en/html/otrs.html#features-of-otrs).

Данный проект - модификация OTRS для применения в РИЦ Информ-Групп

Лицензия
=======
Оригинальная OTRS распространяется по лицензии AFFERO GNU General Public License - смотри
прилагающийся файл [COPYING](COPYING).

Документация
=============
Краткая документация может быть найдена в README.* и полная версия
[онлайн](http://otrs.github.io/doc/). Исходный код OTRS и его публичные расширения
доступны на [github](http://otrs.github.io).

Технические требования
=====================
Perl
- Perl 5.10.0 или выше

Вебсервер
- Вебсервер с поддержкой CGI (CGI не рекомендуется)
- Apache2 + mod_perl2 или выше (рекомендуется)

Базы данных
- MySQL 5.0 или выше
- MariaDB
- PostgreSQL 8.4 или выше
- Oracle 10g или выше

Браузер
- Используйте современный браузер.
- Следующие браузеры не поддерживаются:
  - Internet Explorer до версии 10
  - Firefox до версии 10
  - Safari до версии 5


Директории и файлы
===================
    $HOME (e. g. /opt/otrs/)
    |
    |  (all executables)
    |--/bin/             (all system programs)
    |   |--/otrs.PostMaster.pl      (email2db)
    |   |--/otrs.PostMasterMail.pl  (email2db)
    |   |--/cgi-bin/
    |   |   |----- /index.pl        (Global Agent & Admin handle)
    |   |   |----- /customer.pl     (Global Customer handle)
    |   |   |----- /public.pl       (Global Public handle)
    |   |   |----- /installer.pl    (Global Installer handle)
    |   |   |----- /nph-genericinterface.pl (Global GenericInterface handle)
    |   |--/fcgi-bin/               (If you're using FastCGI)
    |
    |  (all modules)
    |--/Kernel/
    |   |-----/Config.pm      (main configuration file)
    |   |---- /Config/        (Configuration files)
    |   |      |---- /Files/  (System generated, don't touch...)
    |   |
    |   |---- /Output/        (all output generating modules)
    |   |      |---- /HTML/
    |   |             |---- /Templates/
    |   |                    |--- /Standard/*.tt (all tt files for Standard theme)
    |   |
    |   |--- /GenericInterface (GenericInterface framework)
    |          |--- /Invoker/ (invoker backends)
    |          |--- /Mapping/ (data mapping backends)
    |          |--- /Operation/ (operation backends)
    |          |--- /Transport/ (network transport backends)
    |   |
    |   |---- /Language/      (all translation files)
    |   |
    |   |---- /Modules/        (all action modules e. g. QueueView, Move, ...)
    |   |      |----- /Admin*      (all modules for the admin interface)
    |   |      |----- /Agent*      (all modules for the agent interface)
    |   |      |----- /Customer*   (all modules for the customer interface)
    |   |
    |   |---- /System/         (back-end API modules, selection below)
    |           |--- /Auth.pm        (authentication module)
    |           |--- /AuthSession.pm (session authentication module)
    |           |--- /Daemon         (all daemon files)
    |                 |--- /DaemonModules    (all daemon modules)
    |                       |---SchdulerTaskWorker    (all scheduler worker daemon task handlers)
    |           |--- /DB.pm          (central DB interface)
    |           |--- /DB/*.pm        (DB drivers)
    |           |--- /DynamicField.pm (Interface to the DynamicField configuration)
    |           |--- /DynamicField
    |                 |--- /Backend.pm (Interface for using the dynamic fields)
    |                 |--- /Backend/*.pm (DynamicField backend implementations)
    |                 |--- /ObjectType/*.pm (DynamicField object type implementations)
    |           |--- /Email.pm       (create and send e-mail)
    |           |--- /EmailParser.pm (parsing e-mail)
    |           |--- /GenericInterface/*.pm (all DB related GenericInterface modules)
    |           |--- /Group.pm       (group module)
    |           |--- /Log.pm         (log module)
    |           |--- /Queue.pm       (information about queues. e. g. response templates, ...)
    |           |--- /Ticket.pm      (ticket and article functions)
    |           |--- /User.pm        (user module)
    |           |--- /Web/*.pm       (core interface modules)
    |                 |--- /Request.pm    (HTTP/CGI abstraction module)
    |
    |  (data stuff)
    |--/var/
    |   |--/article/               (all incoming e-mails, plain 1/1 and all attachments ...
    |   |                            ... separately (different files), if you want to store on disk)
    |   |--/cron/                  (all cron jobs for escalations and such)
    |   |
    |   |--/fonts/                 (true type fonts for PDF generation)
    |   |
    |   |--/httpd/                 (all static files served by HTTP)
    |   |   |--- /htdocs/
    |   |         |--- /js/        (javascript files for OTRS)
    |   |               |--- /js-cache/        (auto-generated minified JS files)
    |   |               |--- /thirdparty/      (contains jQuery, CKEditor and other external JS libraries)
    |   |         |--- /skins/     (CSS and images for front end)
    |   |               |--- /Agent/        (Agent skins)
    |   |                     |--- /default/ (default skin)
    |   |                           |--- /css/ (stylesheets)
    |   |                           |--- /css-cache/ (auto-generated minified CSS files)
    |   |                           |--- /img/ (images)
    |   |                     |--- /slim/    (additional skin)
    |   |                           |--- /.../ (files)
    |   |                     |--- /ivory/   (additional skin)
    |   |                           |--- /.../ (files)
    |   |               |--- /Customer/     (Customer skins)
    |   |                     |--- /default/ (default skin)
    |   |                           |--- /.../ (files)
    |   |                     |--- /ivory/
    |   |                           |--- /.../ (files)
    |   |
    |   |--/log/                   (log files)
    |   |   |--/TicketCounter.log  (ticket counter)
    |   |
    |   |--/sessions/              (session info)
    |   |
    |   |--/spool/                 (spool files)
    |   |
    |   |--/stats/                 (statistics)
    |   |
    |   |--/tmp/                   (temporary files, such as cache)
    |
    |  (tools stuff)
    |--/scripts/
        |----  /database/
                |--- /otrs-schema.(mysql|postgresql|*).sql (create database script)
                |--- /otrs-initial_insert.(mysql|postgresql|*).sql (all initial sql data - e. g.
                |                                                   root user, queues, ...)
                |--- /otrs-schema-post.(mysql|postgresql|*).sql (create foreign keys script)
