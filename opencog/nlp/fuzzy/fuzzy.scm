
(define-module (opencog nlp fuzzy))

(use-modules (srfi srfi-1)
             (opencog)
             (opencog query)  ; for cog-fuzzy-match
             (opencog nlp)
             (opencog nlp sureal)
             (opencog nlp microplanning))

(define-public (get-answers sent-node)
"
  Find answers (i.e., similar sentences that share some keyword) from
  the Atomspace by using the fuzzy pattern matcher. By default, it
  excludes sentences with TruthQuerySpeechAct and InterrogativeSpeechAct.

  Accepts a SentenceNode as the input.
  Returns one or more sentence strings -- the answers.

  For example:
     (get-answers (car (nlp-parse \"What did Pete eat?\")))
  OR:
     (get-answers (SentenceNode \"sentence@123\"))

  Possible result:
     (Pete ate apples .)
"
    (sent-matching sent-node
        (list (DefinedLinguisticConceptNode "TruthQuerySpeechAct")
              (DefinedLinguisticConceptNode "InterrogativeSpeechAct")))
)

(define-public (sent-matching sent-node exclude-list)
"
  The main function for finding similar sentences
  Returns one or more sentences that are similar to the input one but
  contain no atoms that are listed in the exclude-list.
"
    ; Generate sentences from each of the R2L-SetLinks
    ; (define (generate-sentences r2l-setlinks) (if (> (length r2l-setlinks) 0) (map sureal r2l-setlinks) '()))

    ; Generate sentences for each of the SetLinks found by the fuzzy matcher
    ; TODO: May need to filter out some of the contents of the SetLinks
    ; before sending each of them to Microplanner
; XXX fixme we already know the speech act. Don't do this again.
; Just pas it in as an argument.
    (define (generate-sentences setlinks)
        ; Find the speech act from the SetLink and use it for Microplanning
        (define (get-speech-act setlink)
            (let* ((speech-act-node-name
                        (filter (lambda (name)
                            (if (string-suffix? "SpeechAct" name) #t #f))
                                (map cog-name (cog-filter 'DefinedLinguisticConceptNode (cog-get-all-nodes setlink))))))

                ; If no speech act was found, return "declarative" as default
                (if (> (length speech-act-node-name) 0)
                    (string-downcase (substring (car speech-act-node-name) 0 (string-contains (car speech-act-node-name) "SpeechAct")))
                    "declarative"
                )
            )
        )

        (append-map (lambda (r)
            ; Send each of the SetLinks found by the fuzzy matcher to
            ; Microplanner to see if they are good
            (let ((m-results (microplanning (SequentialAndLink (cog-outgoing-set r)) (get-speech-act r) *default_chunks_option* #f)))
                ; Don't send it to SuReal in case it's not good
                ; (i.e. Microplanner returns #f)
                (if m-results
                    (append-map
                        ; Send each of the SetLinks returned by
                        ; Microplanning to SuReal for sentence generation
                        (lambda (m) (sureal (car m)))
                        m-results
                    )
                    '()
                )
            ))
            setlinks
        )
    )

    (begin
        ; Delete identical sentences from the return set
        (delete-duplicates
            ; Use Mircoplanner and SuReal to generate sentences from the SetLinks found
            (generate-sentences
                ; Search for any similar SetLinks in the atomspace
                (cog-outgoing-set (cog-fuzzy-match
                    ; Get the R2L SetLink of the input sentence
                    (car (cog-chase-link 'ReferenceLink 'SetLink
                        (car (cog-chase-link 'InterpretationLink 'InterpretationNode
                            (car (cog-chase-link 'ParseLink 'ParseNode sent-node))
                        ))
                    ))
                    'SetLink
                    exclude-list
                ))
            )
        )
    )
)
