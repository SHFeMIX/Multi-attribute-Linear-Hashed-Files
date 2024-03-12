// query.c ... query scan functions
// part of Multi-attribute Linear-hashed Files
// Manage creating and using Query objects
// Last modified by John Shepherd, July 2019
#include "defs.h"
#include "query.h"
#include "reln.h"
#include "tuple.h"

// A suggestion ... you can change however you like

struct QueryRep {
	Reln    rel;       
	char   *queryString;  
	Bits    known;
	Bits    unknown;
	PageID  curPageID;     
	int     is_ovp;
	int     next_scan_tup;    // next tuple start to scan in the curPageID
	                          // 下一个要扫描的tuple在是curPage_index中的第几个（1开始）

	int 	nth_page; // if n bits is unknown in depth + 1, 
					  // there will be 2 ^ n  possible pages
					  // 既是查询的第几个page，也是当前查询的pageid的unknown位提取出来拼起来的二进制数的值
	int 	max_n_pages; 
    int     n_page_above_sp;
};

void showBits(Bits bits, char *item) {
	char buf[MAXBITS+1];
	bitsString(bits, buf);
	printf("%s %s\n", buf, item);
}

Bits realID(Reln r, Bits id) {
	Bits pid = getLower(id, depth(r));
	if  (pid < splitp(r)) {
		pid = getLower(id, depth(r) + 1);
	}
	return pid;
}

void count_above_sp_BucketID(Reln r, Bits known, Bits unknown, int *count) {
	if (getLower(unknown, depth(r)) == 0 ) { // all known
		//showBits(known, "need to scan ");
		if (getLower(known, depth(r)) >= splitp(r)) {
			*count += 1;
		}
	}
	else {
		for (int i = 0; i < depth(r); i++) {
			if (bitIsSet(unknown, i) == 1) {
				unknown = unsetBit(unknown, i);
				// let the first unknown bit be 0(unchanged)
				count_above_sp_BucketID(r, known, unknown, count);
				// let the first unknown bit be 1
				count_above_sp_BucketID(r, setBit(known, i), unknown, count);
				break; // only need to get the first one
			}
		}
	}
}

// take a query string (e.g. "1234,?,abc,?")
// set up a QueryRep object for the scan

Query startQuery(Reln r, char *q)
{
	Query new = malloc(sizeof(struct QueryRep));
	assert(new != NULL);

	Bits tuple_hash = tupleHash(r, q);
	char **vals = malloc(nattrs(r)*sizeof(char *));
	tupleVals(q, vals);

	ChVecItem *cv = chvec(r);
	Bits known = 0, unknown = 0;
	int n_unknown_bits = 0;
	for (int i = 0; i < depth(r) + 1; i++) {
		if (strcmp(vals[cv[i].att], "?") == 0) { // unknown
			unknown = setBit(unknown, i);
			n_unknown_bits ++;
		}
		else { // known
			if (bitIsSet(tuple_hash, i) == 1) {
				known = setBit(known, i);
			} // else continue or break, should be the same
		}
	}
	freeVals(vals, nattrs(r));

	new->rel = r;
	new->queryString = q;
	new->known = known;
	new->unknown = unknown;
	new->curPageID = realID(r, known);
	new->is_ovp = 0;
	new->next_scan_tup = 0;

	new->nth_page = 0;
    new->max_n_pages = 1 << n_unknown_bits;
	new->n_page_above_sp = 0;
	count_above_sp_BucketID(r, known, unknown, &new->n_page_above_sp);
    if (getLower(new->curPageID, depth(r)) >= splitp(r)) {
        new->n_page_above_sp --;
    }
	//printf("%d buckets above sp\n", new->n_page_above_sp);

	return new;
}

Bits nextBucketID(Bits known, Bits unknown, int nth_page, int depth) {
	
	int unknown_index = 0;
	for (int i = 0; i < depth; i++) {
		if (bitIsSet(unknown, i) == 1) {
			//把 known 的第i位设置成 nth_page 的第unknown_index位
			if (bitIsSet(nth_page, unknown_index) == 1) {
				known = setBit(known, i);
			}
			else {
				known = unsetBit(known, i);
			}
			unknown_index++;
		}
	}
	
	return known;
}

int get_to_next_bucket(Query q) {
	//printf("get_to_next_bucket:\n");
    Bits nextID = 0;
    while (1) {
        q->nth_page ++;
        if (q->nth_page == q->max_n_pages) {
            return 0;
        }
        nextID = nextBucketID(q->known, q->unknown, q->nth_page, depth(q->rel) + 1);

        if (getLower(nextID, depth(q->rel)) < splitp(q->rel)) {
            break;
        }
        else {
            if (q->n_page_above_sp > 0) {
				 q->n_page_above_sp --;
                break;
            }
        }

    }
	
	q->curPageID = realID(q->rel, nextID);
	//showBits(q->curPageID, "new curPageID");
	q->next_scan_tup = 0;
	q->is_ovp = 0;
	
	return 1;
}

Page curPage_of_q(Query q) { 
	Page curPage = NULL;
	if (q->is_ovp) {
		curPage = getPage(ovflowFile(q->rel), q->curPageID);
	}
	else {
		curPage = getPage(dataFile(q->rel), q->curPageID);
	}
	return curPage;
}

int get_to_next_page(Query q) {
	//printf("get_to_next_page\n");
	Page curr = curPage_of_q(q);

	if (pageOvflow(curr) == NO_PAGE) {
		return 0;
	}

	q->curPageID = pageOvflow(curr);
	q->is_ovp = 1;
	q->next_scan_tup = 0;
	return 1;
}

// get next tuple during a scan

Tuple getNextTuple(Query q)
{
	// printf("/////////////////////\n");
	do {
		// scan curpage until end
		do {
			Page curPage = curPage_of_q(q);
			if (pageNTuples(curPage) == 0) {
				continue;
			}
			Tuple t = pageData(curPage);

			int tup_no_on_page = 0;
			while (1) {
				// tuple is after next_scan and match
				if (tup_no_on_page >= q->next_scan_tup && tupleMatch(q->rel, t, q->queryString)) {
					q->next_scan_tup  = tup_no_on_page + 1;
					// printf("in the end the next_scan_tup is %d======\n", q->next_scan_tup);
					// printf("%d tuples on the page\n                                          ", pageNTuples(curPage));
					return t;
				}	
				if (tup_no_on_page == pageNTuples(curPage) - 1) {
					break;
				}
				else {
					tup_no_on_page ++;
					t += tupLength(t) + 1;
				}
			}

		} while (get_to_next_page(q) == 1);
		
	} while (get_to_next_bucket(q) == 1);

	return NULL;
}

// clean up a QueryRep object and associated data

void closeQuery(Query q)
{
	// TODO
	free(q);
}

