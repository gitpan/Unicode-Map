/* 
 * $Id: Map.xs,v 1.20 1998/02/11 21:30:59 schwartz Exp $
 *
 * ALPHA version
 *
 * Unicode::Map - C extensions
 *
 * Interface documentation at Map.pm
 *
 * Copyright (C) 1998 Martin Schwartz. All rights reserved.
 * This program is free software; you can redistribute it and/or
 * modify it under the same terms as Perl itself.
 *
 * Contact: schwartz@cs.tu-berlin.de
*/

#ifdef __cplusplus
extern "C" {
#endif
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#ifdef __cplusplus
}
#endif

//
//
// "Map.h"
//
//

#define M_MAGIC               0xb827 // magic word
#define MAP8_BINFILE_MAGIC_HI 0xfffe // magic word for Gisle's file format
#define MAP8_BINFILE_MAGIC_LO 0x0001 // 

#define M_END   0       // end
#define M_INF   1       // infinite subsequent entries (default)
#define M_BYTE  2       // 1..255 subsequent entries 
#define M_VER   4       // (Internal) file format revision.
#define M_AKV   6       // key1, val1, key2, val2, ... (default)
#define M_AKAV  7       // key1, key2, ..., val1, val2, ...
#define M_PKV   8       // partial key value mappings
#define M_CKn   10      // compress keys not
#define M_CK    11      // compress keys (default)
#define M_CVn   13      // compress values not
#define M_CV    14      // compress values (default)

#define I_NAME  20      // Info: (wstring) Character Set Name
#define I_ALIAS 21      // Info: (wstring) Charset alias (several entries ok)
#define I_VER   22      // Info: (wstring) Mapfile revision
#define I_AUTH  23 	// Info: (wstring) Mapfile authRess
#define I_INFO  24      // Info: (wstring) Some userEss definable string

#define T_BAD   0	// Type: unknown
#define T_MAP8  1	// Type: Map8 style
#define T_MAP   2	// Type: Map style

#define num1_DEFAULT    M_INF;
#define method1_DEFAULT M_AKV;
#define keys1_DEFAULT   M_CK;
#define values1_DEFAULT M_CV;

U8  _byte(char** buf);
U16 _word(char** buf);
U32 _long(char** buf);

int __get_mode (char** buf, U8* num, U8* method, U8* keys, U8* values);
int __limit_ol (SV* string, SV* o, SV* l, char** ro, U32* rl, U16 cs);
int __read_binary_mapping (SV* bufS, SV* oS, SV* UR, SV* CR);

//
//
// "Map.c"
//
//

U8  _byte(char** buf) { U8*  tmp = (U8*)  *buf; *buf+=1; return (tmp[0]); }
U16 _word(char** buf) { U16* tmp = (U16*) *buf; *buf+=2; return ntohs(tmp[0]); }
U32 _long(char** buf) { U32* tmp = (U32*) *buf; *buf+=4; return ntohl(tmp[0]); }

int
__limit_ol (SV* string, SV* o, SV* l, char** ro, U32* rl, U16 cs) {
//
// Checks, if offset and length are valid. If offset is negative, it is
// treated like a negative offset in perl.
//
// When successful, sets ro (real offset) and rl (real length).
//
   STRLEN  slen;
   char*   address;
   I32     offset;
   U32     length;

   *ro = 0;
   *rl = 0;

   if (!SvOK(string)) {
      if (dowarn) { warn ("String undefined!"); }
      return (0);
   }

   address = SvPV (string, slen);
   offset  = SvOK(o) ? SvIV(o) : 0;
   length  = SvOK(l) ? SvIV(l) : slen;

   if (offset < 0) {
      offset += slen;
   }

   if (offset < 0) {
      offset = 0;
      length = slen;
      if (dowarn) { warn ("Bad negative string offset!"); }
   }

   if (offset > slen) {
      offset = slen;
      length = 0;
      if (dowarn) { warn ("String offset to big!"); }
   }

   if (offset + length > slen) {
      length = slen - offset;
      if (dowarn) { warn ("Bad string length!"); }
   }

   if (length % cs != 0) {
      if (length>cs) {
         length -= (length % cs);
      } else {
         length = 0;
      }
      if (dowarn) { warn("Bad string size!"); }
   }

   *ro = address + offset;
   *rl = length;

   return (1);
}

int
__get_mode (char** buf, U8* num, U8* method, U8* keys, U8* values) {
   U8 type, size;

   type = _byte(buf);
   size = _byte(buf); *buf += size;

   switch (type) {
      case M_INF:
      case M_BYTE:
         *num = type; break;
      case M_AKV:
      case M_AKAV:
      case M_PKV:
         *method = type; break;
      case M_CKn:
      case M_CK:
         *keys = type; break;
      case M_CVn:
      case M_CV:
         *values = type; break;
   }
   return (type);
}

//
//  void = __read_binary_mapping (bufS, oS, UR, CR)
//
//  Table of mode combinations:
//  
//  Mode      | n1  n2  | INF  BYTE  |  CK  CKn  |  CV  CVn
//  ---------------------------------------------------------
//  AKV       |         |            |           |
//  AKAV      |         |            |           |
//  PKV   ok  | ==1 ==1 |      ok    |  ok       |  ok
//
int
__read_binary_mapping (SV* bufS, SV* oS, SV* UR, SV* CR) {
   char* buf;
   ulong o;
   HV* U; SV* uR; HV* u;
   HV* C; SV* cR; HV* c;
   
   int   buflen;
   char* bufmax;
   U8    cs1, cs1b, cs2, cs2b;
   U32   n1, n2;
   U16   check;
   U16   type=T_BAD;
   U8    num1, method1, keys1, values1;
   I16   kn, vn;
   U32   kbegin, vbegin;
   SV*   Ustr;
   SV*   Cstr;
   SV**  tmp_spp;
   
   buf =        SvPVX (bufS);
   o   =        SvIV (oS);
   U   = (HV *) SvRV (UR);
   C   = (HV *) SvRV (CR);

   buflen = SvCUR(bufS); if (buflen < 2) { 
      //
      // Too short file. (No place for magic)
      //
      return (0); 
   }
   bufmax = buf + buflen;
   buf += o;
   check = _word(&buf);

   if (check == M_MAGIC) {
      type = T_MAP;
   } else if (
      ( check == MAP8_BINFILE_MAGIC_HI ) &&
      ( _word(&buf) == MAP8_BINFILE_MAGIC_LO )
   ) {
      type = T_MAP8;
   }

   if (type == T_BAD) {
      return (0);
   }

   num1    = num1_DEFAULT;
   method1 = method1_DEFAULT;
   keys1   = keys1_DEFAULT;
   values1 = values1_DEFAULT;

   while (buf<bufmax) {
      U8 num2, method2, keys2, values2;
      num2=num1; method2=method1; keys2=keys1; values2=values1;

      if (type == T_MAP) {
         cs1 = _byte (&buf);
         if (!cs1) {
            if (__get_mode(&buf, &num1, &method1, &keys1, &values1) == M_END) {
               break;
            }
            continue;
         } else {
            n1  = _byte (&buf);
            cs2 = _byte (&buf);
            n2  = _byte (&buf);
         }
         cs1b = (cs1+7)/8;
         cs2b = (cs2+7)/8;
      } else if (type == T_MAP8) {
         cs1b=1; n1=1; cs2b=2; n2=1;
      }

      Ustr = newSVpvf ("%d,%d,%d,%d", cs1b, n1, cs2b, n2);
      Cstr = newSVpvf ("%d,%d,%d,%d", cs2b, n2, cs1b, n1);

      //
      // Get, create hash for submapping of %U
      //
      if (!hv_exists_ent(U, Ustr, 0)) {
         hv_store_ent(U, Ustr, newRV_inc((SV*) newHV()), 0);
      }
      tmp_spp = hv_fetch(U, SvPVX(Ustr), SvCUR(Ustr), 0);
      if (!tmp_spp) {
         return (0);
      } else {
         uR = (SV *) *tmp_spp;
         u  = (HV *) SvRV (uR);
      }

      //
      // Get, create hash for submapping of %C
      //
      if (!hv_exists_ent(C, Cstr, 0)) {
         hv_store_ent(C, Cstr, newRV_inc((SV*) newHV()), 0);
      }
      tmp_spp = hv_fetch(C, SvPVX(Cstr), SvCUR(Cstr), 0);
      if (!tmp_spp) {
         return (0);
      } else {
         cR = (SV *) *tmp_spp;
         c  = (HV *) SvRV (cR);
      }

      if (type == T_MAP8) {
      //
      // Map8 mode
      //
         //
         // => All (key, value) pairs
         //
         SV* tmpk; SV* tmpv;
         while (buf<bufmax) {
            if (buf[0] != '\0') {
               return 0;
            }
            tmpk = newSVpv(buf+1, 1); buf += 2;
            tmpv = newSVpv(buf  , 2); buf += 2;
            if (buf > bufmax) { break; }

            hv_store_ent(u, tmpk, tmpv, 0);
            hv_store_ent(c, tmpv, tmpk, 0);
         }
      } else if (method1==M_AKV) {
      //
      // Map mode
      //
         //
         // All (key, value) pairs
         //
         U32 ksize = n1*cs1b; SV* tmpk;
         U32 vsize = n2*cs2b; SV* tmpv;
         while (buf<bufmax) {
            tmpk = newSVpv(buf, ksize); buf += ksize;
            tmpv = newSVpv(buf, vsize); buf += vsize;
            if (buf > bufmax) { break; }

            hv_store_ent(u, tmpk, tmpv, 0);
            hv_store_ent(c, tmpv, tmpk, 0);
         }
      } else if (method1==M_AKAV) {
         //
         // First all keys, then all values
         //
         return (0);
      } else if (method1==M_PKV) {
         //
         // Partial 
         //
         if (num1==M_INF) { 
            // no infinite mode
            return (0); 
         } 
         while(buf<bufmax) {
            U8 num3, method3, keys3, values3;
            num3=num2; method3=method2; keys3=keys2; values3=values2;
            if (!(kn = _byte(&buf))) { 
               if (__get_mode(&buf,&num2,&method2,&keys2,&values2)==M_END) {
                  break;
               }
               continue;
            }
            switch (cs1b) {
               case 1: kbegin = _byte(&buf); break;
               case 2: kbegin = _word(&buf); break;
               case 4: kbegin = _long(&buf); break;
               default: return (0);
            }
            while (kn>0) {
               if (values3==M_CV) {
                  //
                  // Partial, keys compressed, values compressed
                  //
                  SV* tmpk; U32 k;
                  SV* tmpv; U32 v;
                  U32 max;
                  vn = _byte(&buf);
                  if (!vn) { 
                     if(__get_mode(&buf,&num3,&method3,&keys3,&values3)==M_END){
                        break;
                     }
                     continue;
                  }
                  if ((n1 != 1) || (n2 != 1)) {
                     //
                     // n (n>1) characters cannot be mapped to one integer
                     //
                     return (0);
                  }
                  switch (cs2b) {
                     case 1: vbegin = _byte(&buf); break;
                     case 2: vbegin = _word(&buf); break;
                     case 4: vbegin = _long(&buf); break;
                     default: return (0);
                  }

                  max = kbegin + vn;
                  for (; kbegin<max; kbegin++, vbegin++) {
               
                     k = htonl(kbegin);
                     tmpk = newSVpv((char *) &k + (4-cs1b), cs1b);
               
                     v = htonl(vbegin);
                     tmpv = newSVpv((char *) &v + (4-cs2b), cs2b);

                     hv_store_ent(c, tmpv, tmpk, 0);
                     hv_store_ent(u, tmpk, tmpv, 0);
                  }
                  kn-=vn;

               } else if (values3==M_CVn) {
                  //
                  // Partial, keys compressed, values not compressed
                  //
                  U32 v;
                  U32 vsize = n2*cs2b;
                  SV* tmpk;
                  SV* tmpv;
                  if (n1 != 1) {
                     return (0);
                  }
                  while (kn--) {
                     v = htonl(kbegin);
                     tmpk = newSVpv((char *) &v + (4-cs1b), cs1b);
                     tmpv = newSVpv(buf, vsize); buf += vsize;

                     hv_store_ent(u, tmpk, tmpv, 0);
                     hv_store_ent(c, tmpv, tmpk, 0);

                     kbegin++;
                  }
               } else {
               //
               // Unknown value compression.
               //
                  return (0);
               }
            }
         }
      } else {
         //
         // unknown method
         //
         return (0);
      }
   };

   return (1);
}

//
//
// "Map.xs"
//
//

MODULE = Unicode::Map	PACKAGE = Unicode::Map

PROTOTYPES: DISABLE

#
# $text = $Map -> reverse_unicode($text)
#
SV*
reverse_unicode(Map, text)
        SV*  Map
        SV*  text

        PREINIT:
        int i; 
        char c;
        STRLEN len; 
        char* str; 

        CODE:
	str = SvPV (text, len);
	if (dowarn && (len % 2) != 0) {
    	   warn("Bad string size!"); len--;
	}
	for (i=0; i<len; i+=2) {
           c=str[i+1]; str[i+1]=str[i]; str[i]=c;
	}

        OUTPUT:
            text

#
# $mapped_str = $Map -> _map_hash($string, \%mapping, $bytesize, offset, length)
#
# bytesize, offset, length in terms of bytes.
#
# bytesize gives the size of one character for this mapping.
#
SV*
_map_hash(Map, string, mappingR, bytesize, o, l)
        SV*  Map
        SV*  string
        SV*  mappingR
        SV*  bytesize
        SV*  o
        SV*  l

        PREINIT:
        char* offset; U32 length; U16 bs;
        char* smax;
        HV*   mapping;
        SV**  tmp;

        CODE:
        bs = SvIV(bytesize);
        __limit_ol (string, o, l, &offset, &length, bs);
        smax = offset + length;

        RETVAL = newSV((length/bs+1)*2);
        mapping = (HV *) SvRV(mappingR);

        for (; offset<smax; offset+=bs) {
           if (tmp = hv_fetch(mapping, offset, bs, 0)) {
              sv_catsv(RETVAL, *tmp); 
           } else {
              /* no mapping character found! */
           }
        }

        OUTPUT:
	   RETVAL


#
# $mapped_str = $Map -> _map_hashlist($string, [@{\%mapping}], [@{$bytesize}])
#
# bytesize gives the size of one character for this mapping.
#
SV*
_map_hashlist(Map, string, mappingRLR, bytesizeLR, o, l)
        SV*  Map
        SV*  string
        SV*  mappingRLR
        SV*  bytesizeLR
        SV*  o
        SV*  l

        PREINIT:
        int j, max;
        AV* mappingRL; HV* mapping;
        AV* bytesizeL; int bytesize;
        SV** tmp;
        char* offset; U32 length; char* smax; 

        CODE:
        __limit_ol (string, o, l, &offset, &length, 1);
        smax = offset + length;

        RETVAL = newSV((length+1)*2);

	mappingRL = (AV *) SvRV(mappingRLR);
        bytesizeL = (AV *) SvRV(bytesizeLR);
        max = av_len(mappingRL);
        if (max != av_len(bytesizeL)) {
	   warn("$#mappingRL != $#bytesizeL!");
	} else {
           max++;
           for (; offset<smax; offset+=2) {
              for (j=0; j<=max; j++) {
                 if (j==max) {
                    /* no mapping character found! */
                 } else {
  	            if (tmp = av_fetch(mappingRL, j, 0)) {
                       mapping = (HV *) SvRV((SV*) *tmp);
                       if (tmp = av_fetch(bytesizeL, j, 0)) {
                          bytesize = SvIV(*tmp);
                          if (tmp = hv_fetch(mapping, offset, bytesize, 0)) {
                             sv_catsv(RETVAL, *tmp); 
                             offset+=bytesize-2;
                             break;
                          }
                       }
                    }
                 }
              }
           }
        }

        OUTPUT:
	   RETVAL


#
# status = $S->_read_binary_mapping($buf, $o, \%U, \%C);
#
int
_read_binary_mapping (MapS, bufS, oS, UR, CR)
	SV* MapS
	SV* bufS
	SV* oS
	SV* UR
	SV* CR

	CODE:
	RETVAL = __read_binary_mapping(bufS, oS, UR, CR);

	OUTPUT:
	   RETVAL


