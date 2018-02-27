#!/usr/bin/env perl

# autoadapt - Automatic quality control for FASTQ sequencing files

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

require 5.18.1;

use strict;
use warnings;

use threads;
use Getopt::Long;
use File::Basename;
use File::Temp qw/ tempfile tempdir /;
use FileHandle;
use IO::Handle;
use File::Spec;

use constant SCRIPT_DIR => File::Spec->rel2abs(dirname(__FILE__));
use constant CUTADAPT_PATH => File::Spec->rel2abs(SCRIPT_DIR . "/tools/cutadapt");
use constant FASTQC_PATH => File::Spec->rel2abs(SCRIPT_DIR . "/tools/fastqc");
use constant FASTQC_CONTAMINANTS_LIST => File::Spec->rel2abs(SCRIPT_DIR . "/tools/install/FastQC/Contaminants/contaminant_list.txt");

use constant DEFAULT_QUALITY_CUTOFF => 20;
use constant DEFAULT_NUM_THREADS => 1;
use constant DEFAULT_MINIMUM_LENGTH => 18;

use constant PROGRAM_NAME => "autoadapt";
use constant VERSION => "0.2";

sub getQualityEncodingBase($);
sub runFastqc($$$);
sub showUsageMessage();
sub ensureFileExists($);
sub ensureCutadaptInstalled();
sub ensureFastqcInstalled();
sub updateContaminantSequences($);
sub updateDetectedContaminantNames($$);
sub runCutadapt($$$$$$$$$;$$);
sub getReverseComplement($);
sub mergeFiles($$$$);
sub splitFile($$$);
sub main();

STDERR->autoflush(1);
STDOUT->autoflush(1);

$SIG{__WARN__} = sub { die @_ };

main();

sub main() {
    my $showHelp;
    my $showVersion;

    # TODO allow quality encoding tyoe to be specified instead of autodetected

    # TODO could autodetect number of CPUs
    my $numThreads = DEFAULT_NUM_THREADS;

    my $qualityCutoff = DEFAULT_QUALITY_CUTOFF;
    my $minimumLength = DEFAULT_MINIMUM_LENGTH;

    GetOptions (
        "quality-cutoff=i" => \$qualityCutoff,
        "threads=i" => \$numThreads,
        "help" => \$showHelp,
        "minimum-length=i" => \$minimumLength,
        "version" => \$showVersion
    );

    if (defined $showHelp) {
        showUsageMessage();
        exit(0);
    }

    if (defined $showVersion) {
        printf("%s %s\n", PROGRAM_NAME, VERSION);
        exit(0);
    }

    if ($numThreads < 1) {
        printf("Sorry, you must use at least 1 thread.\n");
        exit(-1);
    }

    if ($qualityCutoff < 0) {
        printf("Sorry, quality cutoff must be at least 0.\n");
        exit(-1);
    }

    my $unpairedInputFilename;
    my $unpairedOutputFilename;

    my $pairedInputFilename1;
    my $pairedOutputFilename1;

    my $pairedInputFilename2;
    my $pairedOutputFilename2;

    my $usingUnpairedData;

    if (int(@ARGV) == 2) {

        $usingUnpairedData = 1;

        $unpairedInputFilename = File::Spec->rel2abs($ARGV[0]);
        $unpairedOutputFilename = File::Spec->rel2abs($ARGV[1]);

    } elsif (int(@ARGV) == 4) {

        $usingUnpairedData = 0;

        $pairedInputFilename1 = File::Spec->rel2abs($ARGV[0]);
        $pairedOutputFilename1 = File::Spec->rel2abs($ARGV[1]);

        $pairedInputFilename2 = File::Spec->rel2abs($ARGV[2]);
        $pairedOutputFilename2 = File::Spec->rel2abs($ARGV[3]);

    } else {
        showUsageMessage();
        exit(-1);
    }

    if ($usingUnpairedData) {
        system("mkdir -p '" . dirname($unpairedOutputFilename) . "'");
    } else {
        system("mkdir -p '" . dirname($pairedOutputFilename1) . "'");
        system("mkdir -p '" . dirname($pairedOutputFilename2) . "'");
    }

    my $workingDirectory = File::Spec->rel2abs(tempdir(SCRIPT_DIR . "/autoadapt.tmp.XXXXXXXX"));

    if ($usingUnpairedData) {
        ensureFileExists($unpairedInputFilename);
    } else {
        ensureFileExists($pairedInputFilename1);
        ensureFileExists($pairedInputFilename2);
    }

    ensureCutadaptInstalled();
    ensureFastqcInstalled();

    # FastQC
    my %contaminantSequences = ();
    updateContaminantSequences(\%contaminantSequences);

    my %detectedContaminantNames = ();

    my $qualityEncodingBase;

    if ($usingUnpairedData) {
        # unpaired
        my ($fastqcStatus, $fastqcOutput, $fastqcReportPath) = runFastqc(
            $unpairedInputFilename,
            $workingDirectory,
            $numThreads
        );
        if ($fastqcStatus != 0) {
            printf("%s\n", $fastqcOutput);
            printf("\n");
            printf("FastQC failed on file: '%s'\n", $unpairedInputFilename);
            exit(-1);
        } else {
            updateDetectedContaminantNames($fastqcReportPath, \%detectedContaminantNames);
            $qualityEncodingBase = getQualityEncodingBase($fastqcReportPath);
        }
    } else {
        # paired

        my $qualityEncodingBase1;
        my $qualityEncodingBase2;

        # TODO could do this in parallel
        my ($fastqcStatus1, $fastqcOutput1, $fastqcReportPath1) = runFastqc(
            $pairedInputFilename1,
            $workingDirectory,
            $numThreads
        );
        if ($fastqcStatus1 != 0) {
            printf("%s\n", $fastqcOutput1);
            printf("\n");
            printf("FastQC failed on file: '%s'\n", $pairedInputFilename1);
            exit(-1);
        } else {
            updateDetectedContaminantNames($fastqcReportPath1, \%detectedContaminantNames);
            $qualityEncodingBase1 = getQualityEncodingBase($fastqcReportPath1);
        }

        my ($fastqcStatus2, $fastqcOutput2, $fastqcReportPath2) = runFastqc(
            $pairedInputFilename2,
            $workingDirectory,
            $numThreads
        );
        if ($fastqcStatus2 != 0) {
            printf("%s\n", $fastqcOutput2);
            printf("\n");
            printf("FastQC failed on file: '%s'\n", $pairedInputFilename2);
            exit(-1);
        } else {
            updateDetectedContaminantNames($fastqcReportPath2, \%detectedContaminantNames);
            $qualityEncodingBase2 = getQualityEncodingBase($fastqcReportPath2);
        }
        if ($qualityEncodingBase1 eq $qualityEncodingBase2) {
            $qualityEncodingBase = $qualityEncodingBase1;
        } else {
            printf("Paired files do not have the same detected quality score encoding type.\n");
            exit(-1);
        }
    }

    if (int(keys %detectedContaminantNames) > 0) {
        printf("Detected the following known contaminant sequences:\n");
        foreach my $contaminantName (sort keys %detectedContaminantNames) {
            die if (!defined $contaminantSequences{$contaminantName});
            my $contaminantSequence = $contaminantSequences{$contaminantName};
            printf("\t%s (%s)\n", $contaminantName, $contaminantSequence);
        }
    } else {
        printf("No known contaminant sequences were detected.\n");
    }

    # cutadapt

    if ($usingUnpairedData) {
        # unpaired
        my ($status, $output) = runCutadapt(
            $unpairedInputFilename,
            $unpairedOutputFilename,
            \%detectedContaminantNames,
            \%contaminantSequences,
            $workingDirectory,
            $numThreads,
            $qualityEncodingBase,
            $qualityCutoff,
            $minimumLength
        );
        if ($status != 0) {
            printf("%s\n", $output);
            printf("\n");
            printf("cutadapt failed on file: '%s'\n", $unpairedInputFilename);
            exit(-1);
        }
    } else {
        # paired
        my ($status, $output) = runCutadapt(
            $pairedInputFilename1,
            $pairedOutputFilename1,
            $pairedInputFilename2,
            $pairedOutputFilename2,
            \%detectedContaminantNames,
            \%contaminantSequences,
            $workingDirectory,
            $numThreads,
            $qualityEncodingBase,
            $qualityCutoff,
            $minimumLength
        );            
        if ($status != 0) {
            printf("%s\n", $output);
            printf("\n");
            printf("cutadapt failed on files: '%s', '%s'\n", $pairedInputFilename1, $pairedInputFilename2);
            exit(-1);
        }
    }

    # clean up
    system(sprintf("rm -rf %s", $workingDirectory));

    printf("autoadapt completed successfully.\n");
}

sub showUsageMessage() {
    printf("%s %s\n", PROGRAM_NAME, VERSION);
    printf("\n");
    printf("Usage: %s [ <options> ] { <unpaired-in> <unpaired-out> | <paired-in-1> <paired-out-1> <paired-in-2> <paired-out-2> }\n", $0);
    printf("\n");
    printf("Options:\n");
    printf("\t%-25s %s (default: %d)\n",
        "--threads=N",
        "number of threads to use",
        DEFAULT_NUM_THREADS
    );
    printf("\t%-25s %s (default: %d)\n",
        "--quality-cutoff=N",
        "quality cutoff for BWA trimming algorithm",
        DEFAULT_QUALITY_CUTOFF
    );
    printf("\t%-25s %s (default: %d)\n",
        "--minimum-length=N",
        "minimum length of sequences",
        DEFAULT_MINIMUM_LENGTH
    );
}

sub ensureFileExists($) {
    my ($filename) = @_;

    if (! -r $filename) {
        printf("File not found: '%s'\n", $filename);
        exit(-1);
    }
}

sub ensureCutadaptInstalled() {
    if (! -r CUTADAPT_PATH || ! -x CUTADAPT_PATH) {
        printf("cutadapt not found. Please type `make install' and then run %s again.\n", $0);
        exit(-1);
    }
}

sub ensureFastqcInstalled() {
    if (! -r FASTQC_PATH || ! -x FASTQC_PATH) {
        printf("FastQC not found. Please type `make install' and then run %s again.\n", $0);
        exit(-1);
    }
}

sub updateContaminantSequences($) {
    my ($contaminantSequencesRef) = @_;

    open(my $fh, "< " . FASTQC_CONTAMINANTS_LIST) or die "Can't open contaminant sequences list";

    foreach my $line (<$fh>) {
        chomp $line;
        if ($line =~ /^([^#]+?)\t+([^#]+)\s+$/) {
            my $name = $1;
            my $sequence = $2;
            $contaminantSequencesRef->{$name} = $sequence;
        }
    }

    close($fh);
}

sub runFastqc($$$) {
    my ($fastqFilename, $workingDirectory, $numThreads) = @_;

    my $basename = basename($fastqFilename);

    my $fastqcCommand = sprintf("%s --threads %d --outdir %s %s", 
        FASTQC_PATH,
        $numThreads,
        $workingDirectory,
        $fastqFilename
    );
    printf("> %s\n", $fastqcCommand);

    my $output = `$fastqcCommand 2>&1`;
    my $status = $?;

    my $nameWithoutExtension = $basename;
    $nameWithoutExtension =~ s/\.[^\.]+$//g;

    my $fastqcReportPath = sprintf("%s/%s_fastqc/fastqc_data.txt", $workingDirectory, $nameWithoutExtension);

    return ($status, $output, $fastqcReportPath);
}

sub updateDetectedContaminantNames($$) {
    my ($fastqcReportPath, $detectedContaminantNamesRef) = @_;

    open(my $fh, "< $fastqcReportPath") or die "Can't open FastQC report";

    my $inAdaptorSection = 0;

    foreach my $line (<$fh>) {
        chomp $line;

        if ($line =~ />>END_MODULE/) {
            $inAdaptorSection = 0;
        }

        if ($inAdaptorSection) {
            my @fields = split /\t/, $line;
            my $sequence = $fields[0];
            my $count = $fields[1];
            my $percentage = $fields[2];
            my $possibleSource = $fields[3];
            # printf "%s\t%s\t%s\t%s\t\n", $sequence, $count, $percentage, $possibleSource;
            if ($possibleSource !~ /No Hit/) {
                if ($possibleSource =~ /^(.*) \(.*\)$/) {
                    $possibleSource = $1;
                } else {
                    die "Bad format: $possibleSource\n";
                }
                $detectedContaminantNamesRef->{$possibleSource} = 1;
            }
        }

        if ($line =~ /Sequence\s+Count\s+Percentage\s+Possible Source/) {
            $inAdaptorSection = 1;        
        }
    }

    close($fh);
}

sub getQualityEncodingBase($) {
    my ($fastqcReportPath) = @_;

    my $qualityEncodingBase;
    open(my $fh, "< $fastqcReportPath") or die "Can't open FastQC report";
    foreach my $line (<$fh>) {
        chomp $line;
        if ($line =~ /^Encoding/) {
            my @fields = split/\t/, $line;
            my $encodingTypeString = $fields[1];

            if ($encodingTypeString eq "Sanger / Illumina 1.9" ) {
                $qualityEncodingBase = 33;
            } elsif ($encodingTypeString eq "Illumina <1.3" ) {
                $qualityEncodingBase = 59;
            } elsif ($encodingTypeString eq "Illumina 1.3" ) {
                $qualityEncodingBase = 64;
            } elsif ($encodingTypeString eq "Illumina 1.5" ) {
                $qualityEncodingBase = 64;
            } else {
                die "Unknown encoding type: " . $encodingTypeString;
            }

            last;
        }
    }
    close ($fh);

    die "Could not detected quality score encoding type" if (!defined $qualityEncodingBase);

    return $qualityEncodingBase;
}

sub runCutadapt($$$$$$$$$;$$) {
    my @ARGS = @_;
    
    my $unpairedInputFilename;
    my $unpairedOutputFilename;

    my $pairedInputFilename1;
    my $pairedOutputFilename1;

    my $pairedInputFilename2;
    my $pairedOutputFilename2;

    my $detectedContaminantNamesRef;
    my $contaminantSequencesRef;
    my $numThreads;
    my $workingDirectory;

    my $qualityEncodingBase;
    my $qualityCutoff;

    my $minimumLength;

    my $usingUnpairedData;

    if (int(@ARGS) == 9) {

        $usingUnpairedData = 1;
        
        $unpairedInputFilename = $ARGS[0];
        $unpairedOutputFilename = $ARGS[1];

        $detectedContaminantNamesRef = $ARGS[2];
        $contaminantSequencesRef = $ARGS[3];
        $workingDirectory = $ARGS[4];
        $numThreads = $ARGS[5];
        $qualityEncodingBase = $ARGS[6];
        $qualityCutoff = $ARGS[7];
        $minimumLength = $ARGS[8];

    } elsif (int(@ARGS) == 11) {

        $usingUnpairedData = 0;

        $pairedInputFilename1 = $ARGS[0];
        $pairedOutputFilename1 = $ARGS[1];

        $pairedInputFilename2 = $ARGS[2];
        $pairedOutputFilename2 = $ARGS[3];

        $detectedContaminantNamesRef = $ARGS[4];
        $contaminantSequencesRef = $ARGS[5];
        $workingDirectory = $ARGS[6];
        $numThreads = $ARGS[7];
        $qualityEncodingBase = $ARGS[8];
        $qualityCutoff = $ARGS[9];
        $minimumLength = $ARGS[10];

    } else {
        die "Wrong number of arguments";
    }

    die if $numThreads < 1;
    die if $qualityCutoff < 0;

    my $combinedStatus = 0;
    my $combinedOutput = "";

    my $cutadaptArguments = "--format fastq";
    
    # TODO make these configurable
    $cutadaptArguments .= " --match-read-wildcards --times 2 --error-rate 0.2";

    $cutadaptArguments .= sprintf(" --minimum-length %d", $minimumLength);

    $cutadaptArguments .= sprintf(" --quality-cutoff %d --quality-base %d", $qualityCutoff, $qualityEncodingBase);

    foreach my $contaminantName (keys $detectedContaminantNamesRef) {
        die if (!defined $contaminantSequencesRef->{$contaminantName});
        my $sequence = $contaminantSequencesRef->{$contaminantName};

        $cutadaptArguments .= " --anywhere=$sequence";

        # also cut the reverse complement    
        my $reverseComplement = getReverseComplement($sequence);
        $cutadaptArguments .= " --anywhere=$reverseComplement";
    }

    if (int(keys $detectedContaminantNamesRef) == 0) {
        # cutadapt expects there to be at least one adaptor to cut,
        # but we might be filtering on quality or length instead
        # need to supply a dummy adaptor
        $cutadaptArguments .= " --anywhere=X";
    }   

    if ($usingUnpairedData) {
        if ($numThreads == 1) {

            my $cutadaptCommand =
                sprintf("%s %s -o %s %s",
                    CUTADAPT_PATH,
                    $cutadaptArguments,
                    $unpairedOutputFilename,
                    $unpairedInputFilename
                );

            printf "> %s\n", $cutadaptCommand;

            my $output = `$cutadaptCommand 2>&1`;
            my $status = $?;

            $combinedStatus = $status;
            $combinedOutput = $output;

        } elsif ($numThreads > 1) {

            splitFile($unpairedInputFilename, $numThreads, $workingDirectory);

            my @jobs = ();
            for (my $i = 0; $i < $numThreads; $i++) {
                push @jobs, threads->create(sub {

                    my $cutadaptCommand =
                    sprintf("%s %s -o %s %s",
                        CUTADAPT_PATH,
                        $cutadaptArguments,
                        sprintf("%s/%s.split%d", $workingDirectory, basename($unpairedOutputFilename), $i),
                        sprintf("%s/%s.split%d", $workingDirectory, basename($unpairedInputFilename), $i)
                    );  
                    
                    printf "> %s\n", $cutadaptCommand;
                 
                    my $output = `$cutadaptCommand 2>&1`;
                    my $status = $?;

                    return ($status, $output);
                });
            }

            foreach my $job (@jobs) {
                my ($status, $output) = $job->join();
                if ($status != 0) {
                    $combinedStatus = $status;
                }
                $combinedOutput .= $output;
            }   
    
            mergeFiles($unpairedInputFilename, $unpairedOutputFilename, $numThreads, $workingDirectory);
        } else {
            die "Expected at least 1 thread.";      
        }

    } else {
        if ($numThreads == 1) {
            my $cutadaptCommand =
                sprintf("%s %s --paired-output %s -o %s %s %s && %s %s --paired-output %s -o %s %s %s",
                    CUTADAPT_PATH,
                    $cutadaptArguments,
                    sprintf("%s/%s.tmp", $workingDirectory, basename($pairedOutputFilename2)),
                    sprintf("%s/%s.tmp", $workingDirectory, basename($pairedOutputFilename1)),
                    $pairedInputFilename1,
                    $pairedInputFilename2,

                    CUTADAPT_PATH,
                    $cutadaptArguments,
                    $pairedOutputFilename1,
                    $pairedOutputFilename2,
                    sprintf("%s/%s.tmp", $workingDirectory, basename($pairedOutputFilename2)),
                    sprintf("%s/%s.tmp", $workingDirectory, basename($pairedOutputFilename1))
                );

            printf "> %s\n", $cutadaptCommand;

            my $output = `$cutadaptCommand 2>&1`;
            my $status = $?;

            $combinedStatus = $status;
            $combinedOutput = $output;

        } elsif ($numThreads > 1) {
            splitFile($pairedInputFilename1, $numThreads, $workingDirectory);
            
            splitFile($pairedInputFilename2, $numThreads, $workingDirectory);

            my @jobs = ();
            for (my $i = 0; $i < $numThreads; $i++) {
                push @jobs, threads->create(sub {
        
                    my $cutadaptCommand = 
                    sprintf("%s %s --paired-output %s -o %s %s %s && %s %s --paired-output %s -o %s %s %s",

                        CUTADAPT_PATH,
                        $cutadaptArguments,
                        sprintf("%s/%s.tmp.split%d", $workingDirectory, basename($pairedOutputFilename2), $i),
                        sprintf("%s/%s.tmp.split%d", $workingDirectory, basename($pairedOutputFilename1), $i),
                        sprintf("%s/%s.split%d", $workingDirectory, basename($pairedInputFilename1), $i),
                        sprintf("%s/%s.split%d", $workingDirectory, basename($pairedInputFilename2), $i),

                        CUTADAPT_PATH,
                        $cutadaptArguments,
                        sprintf("%s/%s.split%d", $workingDirectory, basename($pairedOutputFilename1), $i),
                        sprintf("%s/%s.split%d", $workingDirectory, basename($pairedOutputFilename2), $i),
                        sprintf("%s/%s.tmp.split%d", $workingDirectory, basename($pairedOutputFilename2), $i),
                        sprintf("%s/%s.tmp.split%d", $workingDirectory, basename($pairedOutputFilename1), $i)
                    );

                    printf "> %s\n", $cutadaptCommand;
                 
                    my $output = `$cutadaptCommand 2>&1`;
                    my $status = $?;

                    return ($status, $output);
                });
            }

            foreach my $job (@jobs) {
                my ($status,$output) = $job->join();
                if ($status != 0) {
                    $combinedStatus = $status;
                }
                $combinedOutput .= $output;
            }

            mergeFiles($pairedInputFilename1, $pairedOutputFilename1, $numThreads, $workingDirectory);

            mergeFiles($pairedInputFilename2, $pairedOutputFilename2, $numThreads, $workingDirectory);

        } else {
            die "Expected at least 1 thread.";
        }
    }

    return ($combinedStatus, $combinedOutput);
}

sub getReverseComplement($) {
    my ($sequence) = @_;

    my $reverseComplement = "";
    for my $character (reverse(split("", $sequence))) {
        my $complement = "";

        if ($character eq "A") {
            $complement = "T";
        } elsif ($character eq "T") {
            $complement = "A";
        } elsif ($character eq "C") {
            $complement = "G";
        } elsif ($character eq "G") {
            $complement = "C";
        } else {
            # TODO allow other characters to pass through unchanged? 
            die;
        }

        $reverseComplement .= $complement;
    }

    return $reverseComplement;
}

sub mergeFiles($$$$) {
    my ($inputFilename, $outputFilename, $n, $workingDirectory) = @_;

    # now we need to piece the output files back togegther
    my @partFiles = ();

    for (my $i = 0; $i < $n; $i++) {
        push @partFiles, FileHandle->new(sprintf("< %s/%s.split%d", $workingDirectory, basename($outputFilename), $i));
    }
    
    open (my $mergedFh, "> $outputFilename") or die;

    # copy to the real input file
    foreach my $partFile (@partFiles) {
        foreach my $line (<$partFile>) {
            chomp $line;
            printf $mergedFh ("%s\n", $line);
        }
    }

    close ($mergedFh);
}

sub splitFile($$$) {
    my ($filename, $n, $workingDirectory) = @_;

    my @partFiles = ();

    for (my $i = 0; $i < $n; $i++) {
        push @partFiles, FileHandle->new(sprintf("> %s/%s.split%d", $workingDirectory, basename($filename), $i));
    }

    open(my $fh, "< $filename") or die;

    my $i = 0;
    my $partFileIndex = 0;

    # TODO make this part go faster (like merging)

    my $currentFile = $partFiles[$partFileIndex];
    foreach my $line (<$fh>) {
        chomp $line;
        $currentFile->printf("%s\n", $line);         

        $i++;

        if ($i % 10000000 == 0) {
            printf "Split %d lines\n", $i;
        }

        if ($i % 40000 == 0) {
            $partFileIndex++;
            if ($partFileIndex == $n) {
                $partFileIndex = 0;
            }
            $currentFile = $partFiles[$partFileIndex];
        }
    }

    close($fh);

    for (my $i = 0; $i < $n; $i++) {
        $partFiles[$i]->close;
    }
}
