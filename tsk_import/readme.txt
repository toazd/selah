The date that this table of contents was created is: 06/28/2011

You have selected to download the TSK (Treasury of Scripture Knowledge). The files included in the downloads are geared to
computer application developers who want to leverage this data into an application they support or wish to build.


Here is a list of the file(s) found in this .zip file:
1.) tskxref.txt - TAB delimited text file. Each line represents a TSK entry associated with a verse.  It is terminated by 
                  a carriage return. 

Here is the structure for the file:

+----------------+---------------+
| Field          | Type          |
+----------------+---------------+
| book_key       | integer       | -> represents the key to the book
| chapter_nbr    | integer       | -> represents the chapter number within the book
| verse_nbr      | integer       | -> represents the verse number within the chapter
| sort_order     | integer       | -> represents the order in which the word should be displayed
| word           | varchar(2028) | -> the TSK word or phrase
| reference_list | varchar(4096) | -> a list of all of the references (in lowercase) that the TSK entry points to.
+----------------+---------------+    abbreviations are used to denote a book (see below for complete list).  all
                                      references are delimited by a semi-colon.
                                      
What follows is a list of the book_key assignments.  All deuterocanonical books numbering begin after Revelation's book 
number assignment.  

+----------+-----------------+
| book_key | book name       |
+----------+-----------------+
|        1 | Genesis         |
|        2 | Exodus          |
|        3 | Leviticus       |
|        4 | Numbers         |
|        5 | Deuteronomy     |
|        6 | Joshua          |
|        7 | Judges          |
|        8 | Ruth            |
|        9 | 1 Samuel        |
|       10 | 2 Samuel        |
|       11 | 1 Kings         |
|       12 | 2 Kings         |
|       13 | 1 Chronicles    |
|       14 | 2 Chronicles    |
|       15 | Ezra            |
|       16 | Nehemiah        |
|       17 | Esther          |
|       18 | Job             |
|       19 | Psalms          |
|       20 | Proverbs        |
|       21 | Ecclesiates     |
|       22 | Song of Solomon |
|       23 | Isaiah          |
|       24 | Jeremiah        |
|       25 | Lamentations    |
|       26 | Ezekiel         |
|       27 | Daniel          |
|       28 | Hosea           |
|       29 | Joel            |
|       30 | Amos            |
|       31 | Obadiah         |
|       32 | Jonah           |
|       33 | Micah           |
|       34 | Nahum           |
|       35 | Habakkuk        |
|       36 | Zephaniah       |
|       37 | Haggi           |
|       38 | Zechariah       |
|       39 | Malachi         |
|       40 | Matthew         |
|       41 | Mark            |
|       42 | Luke            |
|       43 | John            |
|       44 | Acts            |
|       45 | Romans          |
|       46 | 1 Corinthians   |
|       47 | 2 Corinthians   |
|       48 | Galatians       |
|       49 | Ephesians       |
|       50 | Philippians     |
|       51 | Colossians      |
|       52 | 1 Thessalonians |
|       53 | 2 Thessalonians |
|       54 | 1 Timothy       |
|       55 | 2 Timothy       |
|       56 | Titus           |
|       57 | Philemon        |
|       58 | Hebrews         |
|       59 | James           |
|       60 | 1 Peter         |
|       61 | 2 Peter         |
|       62 | 1 John          |
|       63 | 2 John          |
|       64 | 3 John          |
|       65 | Jude            |
|       66 | Revelation      |
+----------+-----------------+

Abbreviations are used for references.  Here is the list:

+----------+-----------------+--------+
| book_key | name            | abbrev |
+----------+-----------------+--------+
|        1 | Genesis         | ge     | 
|        2 | Exodus          | ex     | 
|        3 | Leviticus       | le     | 
|        4 | Numbers         | nu     | 
|        5 | Deuteronomy     | de     | 
|        6 | Joshua          | jos    | 
|        7 | Judges          | jud    | 
|        8 | Ruth            | ru     | 
|        9 | 1 Samuel        | 1sa    | 
|       10 | 2 Samuel        | 2sa    | 
|       11 | 1 Kings         | 1ki    | 
|       12 | 2 Kings         | 2ki    | 
|       13 | 1 Chronicles    | 1ch    | 
|       14 | 2 Chronicles    | 2ch    | 
|       15 | Ezra            | ezr    | 
|       16 | Nehemiah        | ne     | 
|       17 | Esther          | es     | 
|       18 | Job             | job    | 
|       19 | Psalms          | ps     | 
|       20 | Proverbs        | pr     | 
|       21 | Ecclesiates     | ec     | 
|       22 | Song of Solomon | so     | 
|       23 | Isaiah          | isa    | 
|       24 | Jeremiah        | jer    | 
|       25 | Lamentations    | la     | 
|       26 | Ezekiel         | eze    | 
|       27 | Daniel          | da     | 
|       28 | Hosea           | ho     | 
|       29 | Joel            | joe    | 
|       30 | Amos            | am     | 
|       31 | Obadiah         | ob     | 
|       32 | Jonah           | jon    | 
|       33 | Micah           | mic    | 
|       34 | Nahum           | na     | 
|       35 | Habakkuk        | hab    | 
|       36 | Zephaniah       | zep    | 
|       37 | Haggi           | hag    | 
|       38 | Zechariah       | zec    | 
|       39 | Malachi         | mal    | 
|       40 | Matthew         | mt     | 
|       41 | Mark            | mr     | 
|       42 | Luke            | lu     | 
|       43 | John            | joh    | 
|       44 | Acts            | ac     | 
|       45 | Romans          | ro     | 
|       46 | 1 Corinthians   | 1co    | 
|       47 | 2 Corinthians   | 2co    | 
|       48 | Galatians       | ga     | 
|       49 | Ephesians       | eph    | 
|       50 | Philippians     | php    | 
|       51 | Colossians      | col    | 
|       52 | 1 Thessalonians | 1th    | 
|       53 | 2 Thessalonians | 2th    | 
|       54 | 1 Timothy       | 1ti    | 
|       55 | 2 Timothy       | 2ti    | 
|       56 | Titus           | tit    | 
|       57 | Philemon        | phm    | 
|       58 | Hebrews         | heb    | 
|       59 | James           | jas    | 
|       60 | 1 Peter         | 1pe    | 
|       61 | 2 Peter         | 2pe    | 
|       62 | 1 John          | 1jo    | 
|       63 | 2 John          | 2jo    | 
|       64 | 3 John          | 3jo    | 
|       65 | Jude            | jude   | 
|       66 | Revelation      | re     | 
+----------+-----------------+--------+

Best wishes! I hope you find an interesting way to work with this data!