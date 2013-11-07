autoadapt
=========

<pre>
# autoadapt - Automatically detect and remove adaptors in FASTQ files
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

TODO

Install
-------

autoadapt needs special versions of FastQC and cutadapt to be installed. The install happens locally (inside the autoadapt/tools folder).

<pre>
make install
</pre>

Output
------

TODO

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

