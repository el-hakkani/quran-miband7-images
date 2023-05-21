package Quran::Image::Page;

use strict;
use warnings;

use Data::Dumper;
use Mojo::Log;
use base qw/Quran Quran::Image/;

my $log = new Mojo::Log;
sub generate {
	my $self = shift;
	my %opts = @_;

	$self->{_pages}   = $opts{page}   || $opts{pages} || [1..604],
	$self->{_width}   = $opts{width}  || 1024,
	$self->{_output}  = $opts{output} || Quran::ROOT_DIR .'/images/pages/'. $self->{_width} .'/',
	$self->{_gd_text} = new GD::Text or die GD::Text::error;

	my $output  = $self->{_output};
	my $width = $self->{_width};

	# reset the bounding box table before re-running
	$self->db->reset_bounding_box_table();
	if (ref($self->{_pages}) eq 'ARRAY') {
		for my $page (reverse @{ $self->{_pages} }) {
			if ($page >= 1 and $page <= 604) {
				my $image = $self->create($page, $width);
				$self->image->write($output, $page, $image);
			}
		}
	}
	elsif ($self->{_pages} =~ /^[\d]+$/) {
		my $page = $self->{_pages};
		if ($page >= 1 and $page <= 604) {
			my $image = $self->create($page, $width);
			$self->image->write($output, $page, $image);
		}
	}

	return $self;
}

sub create {
	my ($self, $page) = @_;

	$page = {
		number => $page
	};

	print "Page: ". $page->{number} ."\n";

	my $fontfactor = 21;    # 21 is the default
	my $fontdelta = 0.95; #(21 - abs(21 - $fontfactor)) / 21;

	# page 270 font is slightly larger so it goes off the page
	if ($page->{number} == 270){
		$fontfactor = 22.5;
	}

	$page->{width}   = $self->{_width};
	$page->{height}  = $self->{_width} * Quran::Image::PHI * $fontdelta + 30;
	$page->{ptsize}  = int($self->{_width} / $fontfactor);
	$page->{margin_top} = 10;
	$page->{coord_y} = $page->{margin_top};
	$page->{font}    = Quran::Image::FONT_DEFAULT; # TODO: determine font size algorithmically and trim page height to fit or force fit
	$page->{image} = GD::Image->new($page->{width}, $page->{height});
	$page->{color} = {
		#debug => $page->{image}->colorAllocate(225,225,225),
		white => $page->{image}->colorAllocateAlpha(255,255,255,127),
		black => $page->{image}->colorAllocate(0,0,0),
		#red   => $page->{image}->colorAllocate(127,11,19)
		red   => $page->{image}->colorAllocate(19,50,112),
		green   => $page->{image}->colorAllocate(20,110,0)
	};

	$page->{image}->alphaBlending(1);
	$page->{image}->interlaced('true');
	$page->{image}->setAntiAliased( $page->{color}->{black} );

	$page->{lines} = $self->db->get_page_lines($page->{number});

	for (my $i = 0; $i < @{ $page->{lines} }; $i++) {
		my $line = $page->{lines}->[$i];

		$line->{page} = $page;

		$line->{box} = $self->_get_box($line);


		$page->{coord_y} -= $line->{box}->{min_y}
		if $page->{coord_y} <= $page->{margin_top} and $line->{box}->{min_y} < 0;

		$line->{previous_w} = 0;
		$page->{coord_x} = 0;

		for (my $j = 0; $j < @{ $line->{glyphs} }; $j++) {
			my $glyph = $line->{glyphs}->[$j];
			$glyph->{line} = $line;
			$glyph->{box} = $self->_get_box($glyph);

			if ( $line->{type} ne 'sura' and grep { $page->{number} eq $_ } qw/1 2/  ) {
				# $glyph->{use_coord_y} = 1;
				# $glyph->{box}{coord_y} += 100;
				# $glyph->{y_offset} = 100;
				#         $log->info( 'hmm' );
				#         $log->info( Dumper $page );
				#         exit 0;
			}

			if ($glyph->{position} == 1 and $line->{type} eq 'sura') {
				my $glyph = $self->db->get_ornament_glyph('header-box');
				$glyph->{line} = $line;

				$glyph->{ptsize} = $page->{ptsize} * 1;

				$glyph->{box} = $self->_get_box($glyph);

				$glyph->{use_coords} = 1;

				$glyph->{box}->{coord_y} = $page->{coord_y} - 10;
				$glyph->{box}->{coord_y} -= $glyph->{box}->{char_down};

				$self->_set_box($glyph);
			}

			$page->{coord_x} = $page->{coord_x} ?
			$page->{coord_x} + $line->{previous_w} :
			$line->{box}->{coord_x};

			$line->{previous_w} = $glyph->{box}->{max_x};

			if ($line->{type} eq 'sura') {
				$glyph->{use_coord_y} = 1;
				$glyph->{box}->{coord_y} = $page->{coord_y};
				$glyph->{box}->{coord_y} += $line->{box}->{height} / 7;
			}

			$glyph->{box} = $self->_set_box($glyph);

			$line->{box} = $self->_get_max_box($glyph->{box}, $line->{box});
		}

		$page->{coord_y} -= $line->{box}->{char_down};
		$page->{coord_y} += 2 * $line->{box}->{char_up} + (($i+1) % 3 == 0 ? 10 : 0);

	}

	return $page->{image};
}

sub _set_box {
	my ($self, $glyph) = @_;

	my $line = $glyph->{line}? $glyph->{line} : $glyph;
	my $page = $line->{page};

	my $font   = $glyph->{font}   || $line->{font}   || $page->{font};
	my $ptsize = $glyph->{ptsize} || $line->{ptsize} || $page->{ptsize};

	my $box = $glyph->{box};

	my $color = $page->{color}->{black};

	if ($line->{type} eq 'ayah') {
		my $gt = $self->db->_get_glyph_type($glyph->{text}, $page->{number});
		$color = $self->_should_color($glyph->{text}, $page->{number},
		  $line->{type}, $gt) ?
			$page->{color}->{red} : $page->{color}->{black};
	}
	elsif ($line->{type} eq 'sura') { 
		$color = $page->{color}->{green};
	}

	# begin hack
	my ($coord_x, $coord_y) = $glyph->{use_coords} ? ($glyph->{box}->{coord_x}, $glyph->{box}->{coord_y}) : ($page->{coord_x}, $page->{coord_y});
	$coord_x = $glyph->{box}->{coord_x} if $glyph->{use_coord_x};
	$coord_y = $glyph->{box}->{coord_y} if $glyph->{use_coord_y};
	# end of hack

	if ($line->{type} eq 'ayah') {
		my ($min_x, $max_x, $min_y, $max_y) = (undef, undef, undef, undef);

		$min_x = $page->{coord_x} + $glyph->{box}->{min_x};
		$min_x = int($min_x);
		$max_x = $min_x + ($glyph->{box}->{max_x} - $glyph->{box}->{min_x});
		$max_x = int($max_x + 0.5);

		$min_y = $page->{coord_y} + $glyph->{box}->{min_y};
		$min_y = int($min_y);
		$max_y = $min_y + ($glyph->{box}->{max_y} - $glyph->{box}->{min_y});
		$max_y = int($max_y + 0.5);

		if ($glyph->{y_offset}) {
			# used to ensure coordinates for pages 1 and 2 reflect additional
			# offset added to space sura header and sura text.
			#     $log->info("here with " . $glyph->{y_offset});
			$min_y = $min_y + $glyph->{y_offset};
			$max_y = $max_y + $glyph->{y_offset};
		}

		$self->db->set_page_line_bbox($glyph->{page_line_id}, $page->{width}, $min_x, $max_x, $min_y, $max_y);
	}

	$page->{image}->stringFT($color, $font, $ptsize, 0, $coord_x, $coord_y, $glyph->{text}, {
		resolution => '96,94',
		kerning => 0
	});

	return $box;
}

sub _get_box {
	my ($self, $glyph) = @_;

	my $line = $glyph->{line}? $glyph->{line} : $glyph;
	my $page = $line->{page};

	my $font   = $glyph->{font}   || $line->{font}   || $page->{font};
	my $ptsize = $glyph->{ptsize} || $line->{ptsize} || $page->{ptsize};

	# we recently changed these 3 fonts to fix some artifacts (extra lines or
	# pixels in them). the exported font in fontforge causes char_up and
	# char_down values to be different. i couldn't figure out a way to fix
	# this in the font itself, so in those cases, just read the values from
	# one of the other font files (in this case, BSML.ttf) and use them. the
	# values seem to be the same across all the original fonts.

	my $adjustedUp = 0;
	my $adjustedDown = 0;
	my $shouldAdjust = 0;

	if ($font =~ /P105/ || $font =~ /P237/ || $font =~ /P552/ || $font =~ /P554/) {
		$self->{_gd_text}->set(
		font   => $page->{font},
		ptsize => $ptsize
		);
		$shouldAdjust = 1;
		$adjustedUp = $self->{_gd_text}->get('char_up');
		$adjustedDown = $self->{_gd_text}->get('char_down');
	}

	$self->{_gd_text}->set(
	font   => $font,
	ptsize => $ptsize
	);
	$self->{_gd_text}->set_text( $glyph->{text} );

	my ($space, $char_down, $char_up) = $self->{_gd_text}->get('space', 'char_down', 'char_up');

	# see comment above
	if ($shouldAdjust) {
		$char_up = $adjustedUp;
		$char_down = $adjustedDown;
	}

	# @bbox[0,1]  Lower left corner (x,y)
	# @bbox[2,3]  Lower right corner (x,y)
	# @bbox[4,5]  Upper right corner (x,y)
	# @bbox[6,7]  Upper left corner (x,y)

	my @bbox = GD::Image->stringFT($page->{color}->{black}, $font, $ptsize, 0, 0, 0, $glyph->{text});
	my $min_x = List::Util::min($bbox[0], $bbox[6]);
	my $max_x = List::Util::max($bbox[4], $bbox[2]);
	my $min_y = List::Util::min($bbox[7], $bbox[5]);
	my $max_y = List::Util::max($bbox[1], $bbox[3]);

	my $width = $max_x;# - $min_x;
	my $height = $max_y - $min_y;

	my $coord_x = ($page->{width} - $width) / 2;
	my $coord_y = $page->{coord_y};

	return {
		coord_x   => $coord_x,
		coord_y   => $coord_y,
		min_x     => $min_x,
		max_x     => $max_x,
		min_y     => $min_y,
		max_y     => $max_y,
		space     => $space,
		char_down => $char_down,
		char_up   => $char_up,
		width     => $width,
		height    => $height,
		bbox      => \@bbox,
		corner    => {
			top => {
				left  => [$bbox[6],$bbox[7]],
				right => [$bbox[4],$bbox[5]]
			},
			bottom => {
				left  => [$bbox[0],$bbox[1]],
				right => [$bbox[2],$bbox[3]]
			}
		}
	};
}

sub _get_max_box {
	my $self = shift;
	my ($box_a, $box_b) = @_;
	my $box_c;
	my @lt = qw/min_x min_y char_down coord_x coord_y/;
	my @gt = qw/max_x max_y space char_up width height/;
	for (@lt) {
		$box_c->{$_} = ($box_a->{$_} <= $box_b->{$_})? $box_a->{$_} : $box_b->{$_};
	}
	for (@gt) {
		$box_c->{$_} = ($box_a->{$_} >= $box_b->{$_})? $box_a->{$_} : $box_b->{$_};
	}
	return $box_c;
}

1;
__END__
