#!/usr/bin/perl
use 5.006;
use strict;
use warnings;
use Test::More;
use Init::Service;

plan tests => 24;

# Force the unknown init system
diag "--- Test forced UNKNOWN init system ---";
my $svc = Init::Service->new(useinit => Init::Service::INIT_UNKNOWN);
ok $svc, "Created object";
like $svc->error, qr{unknown init system}i, "Unknown init is an error";
is $svc->initsys, Init::Service::INIT_UNKNOWN, "correct init system";

like $svc->load(), qr{unknown init system}i,
    "load()    returns error as it should";
like $svc->add(), qr{unknown init system}i,
    "add()     returns error as it should";
like $svc->enable(), qr{unknown init system}i,
    "enable()  returns error as it should";
like $svc->start(), qr{unknown init system}i,
    "start()   returns error as it should";
like $svc->stop(), qr{unknown init system}i,
    "stop()    returns error as it should";
like $svc->disable(), qr{unknown init system}i,
    "disable() returns error as it should";
like $svc->remove(), qr{unknown init system}i,
    "remove()  returns error as it should";

# Try whatever the normal one is - non priv tests
diag " ";
diag "--- Test local system's init system ---";
$svc = Init::Service->new;
ok $svc, "Created object";
is $svc->error, q{}, "No errors when created";
isnt $svc->initsys, Init::Service::INIT_UNKNOWN,
    "init system is known: " . $svc->initsys;

# Try to load a service we (hope) does not exist
diag " ";
diag "--- Try to load() bogus service";
$svc = Init::Service->new;
$svc->load("bogus-foobarbaz");
like $svc->error, qr{No such service}i, "Returns correct error";

# Load a known (hopefully) service - ssh
diag " ";
diag "--- Load a known service ---";
$svc = Init::Service->new;
$svc->load("ssh");
SKIP: {
    skip "ssh service not on this system", 6
        unless $svc->error !~ m/no such service/i;
    is $svc->error,      q{},   "Lookup went ok";
    is $svc->name,       "ssh", "Loaded name";
    isnt $svc->type,     q{},   "Loaded type: " . $svc->type;
    isnt $svc->run,      q{},   "Loaded run: " . $svc->run;
    isnt $svc->initfile, q{},   "Loaded initfile: " . $svc->initfile;
    isnt $svc->initsys,  q{},   "Loaded initsys: " . $svc->initsys;
}

# Test option variations
diag " ";
diag "--- Option variations ---";
$svc = new Init::Service(title => "The bar daemon", run => "/bin/true");
is $svc->error, q{}, "Basic new(), normal opts";
$svc = new Init::Service(TiTlE => "The bar daemon", rUN => "/bin/true");
is $svc->error, q{}, "Basic new(), mixed case opts";
$svc = new Init::Service(-tiTLE=> "The bar daemon", -ruN => "/bin/true");
is $svc->error, q{}, "Basic new(), dash opts";

$svc = new Init::Service(-NAME => "fiz-daemon", blahblah => "/bin/true");
like $svc->error, qr{bad option}i, "bogus option caught";

exit 0;

