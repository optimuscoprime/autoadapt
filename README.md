autoadapt
=========

<pre>
# autoadapt - Automatic quality control for FASTQ sequencing files
# Copyright (C) 2013  Rupert Shuttleworth
# optimuscoprime@gmail.com

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
</pre>

Overview
--------

As of November 2013, the NCBI Sequence Read Archive contains over three million gigabytes of publicly available DNA and RNA sequencing files. However, there is a wide variety of sequencing adaptors and primers which may be contaminating each file, and these sequences need to be removed before doing any further analysis. 

We developed a tool to automatically detect which adaptors and primers are present in a FASTQ file and remove those sequences from the file, as well as detecting the quality score encoding type used and removing low quality sequences.

We currently make heavy use of FastQC and cutadapt, both of which are included in the tools folder.

Install
-------

autoadapt needs special versions of FastQC and cutadapt to be installed. The install happens locally (inside the autoadapt/tools folder). Type:

<pre>
make install
</pre>

Usage
-----

<pre>
autoadapt 0.1

Usage: ./autoadapt.pl [ &lt;options&gt; ] { &lt;unpaired-in&gt; &lt;unpaired-out&gt; | &lt;paired-in-1&gt; &lt;paired-out-1&gt; &lt;paired-in-2&gt; &lt;paired-out-2&gt; }

Options:
    --threads=N               number of threads to use (default: 1)
    --quality-cutoff=N        quality cutoff for BWA trimming algorithm (default: 20)
    --minimum-length=N        minimum length of sequences (default: 18)
</pre>

Technical details
-----------------

First we run FastQC to determine the quality score encoding type (e.g. phred33, phred64) and to look for any over-represented sequences that match against known adaptors and primers in the FastQC contaminants_list.txt file.

Then, the sequences for any detected contaminants (primers, adaptors, etc.) are removed using cutadapt. In addition, cutadapt can also remove low quality sequences and sequences that are shorter than a minimum length.

In order to speed up the trimming process, cutadapt can also be run in parallel on small chunks of the original FASTQ file. When specifying the number of threads to use, you should consider how many CPUs are available and how fast your hard drive is to read and write data from.

