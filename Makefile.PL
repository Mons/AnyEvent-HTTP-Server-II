use 5.008008;
use ExtUtils::MakeMaker;
BEGIN{ $ENV{AUTHOR} and require CPAN::Meta and CPAN::Meta->import();  };

WriteMakefile(
	NAME              => 'AnyEvent::HTTP::Server',
	VERSION_FROM      => 'lib/AnyEvent/HTTP/Server.pm',
	PREREQ_PM         => {
		AnyEvent       => 5,
		'Digest::SHA1' => 2,
		'JSON::XS'     => 3,
		'HTTP::Easy'   => 0.02,
	},
	ABSTRACT_FROM     => 'lib/AnyEvent/HTTP/Server.pm', # retrieve abstract from module
	AUTHOR            => 'Mons Anderson <mons@cpan.org>',
	LICENSE           => 'perl',
	PL_FILES          => { "Kit.pm.PL" => '$(INST_LIB)/AnyEvent/HTTP/Server/Kit.pm' },
	clean             => { FILES => "Kit.pm" },
);
