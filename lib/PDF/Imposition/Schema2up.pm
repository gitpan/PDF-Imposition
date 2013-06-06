package PDF::Imposition::Schema2up;
use strict;
use warnings;
use base "PDF::Imposition::Schema";

=head1 NAME

PDF::Imposition::Schema2up - Imposition schema 2up (booklet)

=head1 SYNOPSIS

    use PDF::Imposition::Schema2up;
    my $imposer = PDF::Imposition::Schema2up->new(
                                                  signature => "10-20",
                                                  file => "test.pdf",
                                                  output => "out.pdf",
                                                  cover => 1,
                                                 );
    # or call the methods below to set the values, and then call:
    $imposer->impose;

The output pdf will be in C<$imposer->output>

=head1 SCHEMA EXPLANATION

This schema is a variable and dynamic method. The signature, i.e., the
booklets which compose the document, are not fixed-sized, but can be
altered. The purpose is to have 1 or more booklets that you print
recto-verso and just fold to have your home-made book (this schema is
aimed to DIY people).

Say you have a text with 60 pages in A5: you would print it on A4,
double-side, take the pile out of the printer, fold it and clip it.

The schema looks like (for a signature of 8 pages on 2 sheets):

       RECTO S.1     VERSO S.1
     +-----+-----+  +-----+-----+ 
     |     |     |  |     |     | 
     |  8  |  1  |  |  2  |  7  | 
     |     |     |  |     |     | 
     +-----+-----+  +-----+-----+ 

       RECTO S.2     VERSO S.2
     +-----+-----+  +-----+-----+
     |     |     |  |     |     |
     |  6  |  3  |  |  4  |  5  |
     |     |     |  |     |     |
     +-----+-----+  +-----+-----+

=head1 METHODS

=head2 Public methods

=head3 signature

The signature, must be a multiple of 4, or a range, like the string
"20-100". If a range is selected, the signature is determined
heuristically to minimize the white pages left on the last signature.
The wider the range, the best the results.

This is useful if you are doing batch processing, and you don't know
the number of page in advance (so you can't tweak the source pdf to
have a suitable number of page via text-block dimensions or font
changes).

Typical case: you define a signature of 60 pages, and your PDF happens
to have 61 pages. How unfortunate, and you just can't put out a PDF
with 59 blank pages. The manual solution is to change something in the
document to get it under 60 pages, but this is not always viable or
desirable. So you define a dynamic range for signature, like 20-60,
(so the signature will vary between 20 and 60) and the routine will
find the best one, which happens to be 32 (with 3 blank pages).

If no signature is specified, the whole text will be imposed on a
single signature, regardeless of its size.

Es.

  $imposer->signature("20-60");

Keep in mind that a signature with more than 100 pages is not suitable
to be printed and folded at home (too thick).

=cut

sub signature {
    my $self = shift;
    if (@_ == 1) {
        $self->{signature} = shift;
    }
    my $sig = $self->{signature} || 0;
    return $self->_optimize_signature($sig) + 0; # force the scalar context
}

sub _optimize_signature {
    my ($self, $sig, $total_pages) = @_;
    unless ($total_pages) {
        $total_pages = $self->total_pages;
    }
    return 0 unless $sig;
    if ($sig =~ m/^[0-9]+$/s) {
        die "Signature must be a multiple of four" if $sig % 4;
        return $sig;
    }
    my ($min, $max);
    if ($sig =~ m/^([0-9]+)?-([0-9]+)?$/s) {
        $min = $1 || 4;
        $max = $2 || $total_pages;
        $min = $min + ((4 - ($min % 4)) % 4);
        $max = $max + ((4 - ($max % 4)) % 4);
        die "Bad range $max - $min" unless $max > $min;
        die "bad min $min" if $min % 4;
        die "bad max $max" if $max % 4;
    }
    else {
        die "Unrecognized range $sig";
    }
    my $signature = 0;
    my $roundedpages = $total_pages + ((4 - ($total_pages % 4)) % 4);
    my $needed = $roundedpages - $total_pages;
    die "Something is wrong" if $roundedpages % 4;
    if ($roundedpages <= $min) {
        wantarray ? return ($roundedpages, $needed) : return $roundedpages;
    }
    $signature = $self->_find_signature($roundedpages, $max);
    if ($roundedpages > $max) {
        while ($signature < $min) {
            $roundedpages += 4;
            $needed += 4;
            $signature = $self->_find_signature($roundedpages, $max)
        }
    }
    # warn "Needed $needed blank pages";
    wantarray ? return ($signature, $needed) : return $signature;
}

sub _find_signature {
    my ($self, $num, $max) = @_;
    die "not a multiple of four" if $num % 4;
    die "uh?" unless $num;
    my $i = $max;
    while ($i > 0) {
        # check if the the pagenumber is divisible by the signature
        # with modulo 0
        # warn "trying $i for $num / max $max\n";
        if (($num % $i) == 0) {
            return $i;
        }
        $i -= 4;
    }
    warn "Looped ended with no result\n";
}


=head3 cover

This option is only used when the 2up or 2down schema is asked, i.e.,
when a variable signature is needed. Often it happens that we want the
last page of the pdf to be the last on the physical booklet. The
original algorithm just fills the signature with blank pages. If
C<cover> is set to a true value, the last page of the logical pdf will
be placed on the last page of the last signature.

Es.

  $imposer->cover(1);

=cut

sub cover {
    my $self = shift;
    if (@_ == 1) {
        $self->{cover} = shift;
    }
    return $self->{cover};
}

=head3 impose

Do the job and leave the output in C<< $self->outfile >>

=cut

=head2 Internal (but documented) methods

=head3 page_sequence_for_booklet($pages, $signature)

Algorithm taken/stolen from C<psbook> (Angus J. C. Duggan 1991-1995).
The C<psutils> are still a viable solution if you want to go with
PDF->PS->PDF route.

=cut

sub page_sequence_for_booklet {
    my ($self, $pages, $signature) = @_;
    unless (defined $pages) {
        $pages = $self->total_pages;
    }
    unless (defined $signature) {
        $signature = $self->signature;
    }
    my (@pgs, $maxpage);
    use integer;
    if (!$signature) {
        # rounding 
        $signature = $maxpage = $pages + ((4 - ($pages % 4)) % 4);
    }
    else {
        $maxpage = $pages + (($signature - ($pages % $signature)) % $signature)
    }
    for (my $currentpg = 0; $currentpg < $maxpage; $currentpg++) {
        my $actualpg = $currentpg - ($currentpg % $signature);
        my $modulo = $currentpg % 4;
        if ($modulo == 0 or $modulo == 3) {
            $actualpg += $signature - 1 - (($currentpg % $signature) / 2);
        }
        elsif ($modulo == 1 or $modulo == 2) {
            $actualpg += ($currentpg % $signature) / 2;
        }
        if ($actualpg < $pages) {
            $actualpg++;
        } else {
            $actualpg = undef;
        }
        push @pgs, $actualpg;
    }
    my @out;
    # if we want a cover, we need to find the index of the last page,
    # and the first undef page, which could be at the beginning of the
    # last signature, so we have to scan the array.
    if ($self->cover) {
        my $last;
        my $firstundef;
        for (my $i = 0; $i < @pgs; $i++) {
            if ($pgs[$i] and $pgs[$i] == $pages) {
                $last = $i;
            }
        }
        for (my $i = 0; $i < @pgs; $i++) {
            if (not defined $pgs[$i]) {
                $firstundef = $i;
                last;
            }
        }
        if (defined $firstundef) {
            # there is an undef, so swap;
            $pgs[$firstundef] = $pgs[$last];
            $pgs[$last] = undef;
        }
        else {
            warn "Nothing to do? $firstundef, $last";
        }
    }
    while (@pgs) {
        push @out, [ shift(@pgs), shift(@pgs) ];
    }
    return \@out;
}

sub impose {
    my $self = shift;
    # prototype
    $self->out_pdf_obj->mediabox(
                                 $self->orig_width * 2,
                                 $self->orig_height,
                                );
    my $seq = $self->page_sequence_for_booklet;
    foreach my $p (@$seq) {
        # loop over the pages
        my $left = $p->[0];
        my $right = $p->[1];
        my $page = $self->out_pdf_obj->page();
        my $gfx = $page->gfx();
        if (defined $left) {
            my $lpage = $self->out_pdf_obj
              ->importPageIntoForm($self->in_pdf_obj, $left);
            $gfx->formimage($lpage, 0, 0);
        }
        if (defined $right) {
            my $rpage = $self->out_pdf_obj
              ->importPageIntoForm($self->in_pdf_obj, $right);
            $gfx->formimage($rpage, $self->orig_width, 0);
        }
    }
    $self->out_pdf_obj->saveas($self->outfile);
    return $self->outfile;
}

1;

=head1 SEE ALSO

L<PDF::Imposition>

=cut
