module Bailador;
use Bailador::Request;
use Bailador::Response;
use Ratel;
use HTTP::Easy::PSGI;

my %routes;
%routes<GET>  = [];
%routes<POST> = [];

my $current-request  = Bailador::Request.new;
my $current-response = Bailador::Response.new;
my $template-engine  = Ratel.new;

sub route_to_regex($route) {
    $route.split('/').map({
        my $r = $_;
        if $_.substr(0, 1) eq ':' {
            $r = q{(<-[\/\.]>+)};
        }
        $r
    }).join("'/'");
}

multi parse_route(Str $route) {
    my $r = route_to_regex($route);
    return / ^ <_capture=$r> $ /
}

multi parse_route($route) {
    # do nothing
    $route
}

sub get(Pair $x) is export {
    my $p = parse_route($x.key) => $x.value;
    %routes<GET>.push: $p;
    return $x;
}

sub post(Pair $x) is export {
    my $p = parse_route($x.key) => $x.value;
    %routes<POST>.push: $p;
    return $x;
}

sub request is export { $current-request }

sub content_type(Str $type) is export {
    $current-response.headers<Content-Type> = $type;
}

sub status(Int $code) is export {
    $current-response.code = $code;
}

sub template(Str $tmpl, %params = {}) is export {
    $template-engine.load("views/$tmpl");
    return $template-engine.render(|%params);
}

sub dispatch($env) {
    my $res = '';

    $current-request.env      = $env;
    $current-response.code    = 404;
    $current-response.content = 'Not found';
    $current-response.headers<Content-Type> = 'text/html';

    for %routes{$env<REQUEST_METHOD>}.list -> $r {
        next unless $r;
        if $env<REQUEST_URI> ~~ $r.key {
            $current-response.code = 200;
            if $/ {
                unless $/[0] { $/ = $/<_capture> }
                $current-response.content = $r.value.(|$/.list);
            } else {
                $current-response.content = $r.value.();
            }
        }
    }
    return $current-response.psgi;
}

sub baile is export {
    given HTTP::Easy::PSGI.new(port => 3000) {
        .app(&dispatch);
        .run;
    }
}