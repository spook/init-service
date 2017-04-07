#!/usr/bin/perl
use 5.006;
use strict;
use warnings;
use Test::More;
use System::Service;

plan tests => 18;

# Force the unknown init system
note "--- Test forced UNKNOWN init system ---";
my $svc = System::Service->new(initsys => System::Service::INIT_UNKNOWN);
ok $svc, "Created object";
like $svc->error, qr{unknown init system}i, "Unknown init is an error";
is $svc->initsys, System::Service::INIT_UNKNOWN, "correct init system";

like $svc->load(),    qr{unknown init system}i, "load()    returns error as it should";
like $svc->add(),     qr{unknown init system}i, "add()     returns error as it should";
like $svc->enable(),  qr{unknown init system}i, "enable()  returns error as it should";
like $svc->start(),   qr{unknown init system}i, "start()   returns error as it should";
like $svc->stop(),    qr{unknown init system}i, "stop()    returns error as it should";
like $svc->disable(), qr{unknown init system}i, "disable() returns error as it should";
like $svc->remove(),  qr{unknown init system}i, "remove()  returns error as it should";

# Try whatever the normal one is  - non priv tests
note " ";
note "--- Test local system's init system ---";
$svc = System::Service->new;
ok $svc, "Created object";
is $svc->error, q{}, "No errors when created";
isnt $svc->initsys, System::Service::INIT_UNKNOWN, "init system is known: " . $svc->initsys;

# Try to load a service we (hope) does not exist
note " ";
note "--- Try to load() bogus service";
$svc = System::Service->new;
$svc->load("bogus-foobarbaz");
like $svc->error, qr{No such service}i, "Returns correct error";

# Load a known (hopefully) service - ssh
note " ";
note "--- Load a known service ---";
$svc = System::Service->new;
$svc->load("ssh");
SKIP: {
    skip "ssh service not on this system", 4
        unless $svc->error !~ m/no such service/i;
    is $svc->error,     q{},   "Lookup went ok";
    is $svc->name,      "ssh", "Loaded name";
    isnt $svc->type,    q{},   "Loaded type: " . $svc->type;
    isnt $svc->command, q{},   "Loaded command: " . $svc->command;
}

exit 0;

