default: install

clean:
	rm -rf autoadapt.tmp.*

install:
	./tools/install-cutadapt.sh
	./tools/install-fastqc.sh
